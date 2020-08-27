//
//  ViewController.swift
//  Test Strage M
//
//  Created by うに on 2020/08/25.
//  Copyright © 2020 うに. All rights reserved.
//

import Cocoa

class ViewController: NSViewController, USBDetectorDelegate {

    @IBOutlet var logView: NSTextView!
    @IBOutlet weak var actionButton: NSButton!
    @IBOutlet weak var volumeList: NSPopUpButton!
    @IBOutlet weak var indicator: NSLevelIndicator!
    
    typealias StatFS = statfs // this does the trick
    
    class Volume {
        
        init() {
            
        }
        
        init( url: URL, volumeName: String, dispString: String ) {
            var fs: StatFS = StatFS()
            if statfs(url.path, &fs) == 0 {
                self.path = url.path
                self.name = volumeName
                self.blockSize = (UInt64)(fs.f_bsize)
                self.blocks = fs.f_blocks
                self.freeBlock = fs.f_bfree
                self.dispString = dispString
                
                return
            }
        }
        
        // フリーブロックの更新
        func upateFreeBlock() {
            var fs: StatFS = StatFS()
            if statfs(self.path, &fs) == 0 {
                self.freeBlock = fs.f_bfree
            }
        }
        
        func isAvailable() -> Bool {
            return self.blocks > 0
        }
        
        var path: String = "/"
        var name: String = ""
        var blockSize: UInt64 = 0
        var blocks: UInt64 = 0
        var freeBlock: UInt64 = 0
        var dispString: String = ""
    }
    
    var logText: String = ""        // ログテキスト
    var volumeArray: Array<Volume> = Array()    // ストレージの情報配列
    var fileCount: Int = -1         // ファイルカウント
    var isInterrupt: Bool = false   // 強制終了フラグ
    var indicatorSub: Double = 0.0  // インジケーター最大数
    let detector = USBDetector()    // USBデバイス検知
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        refreshVolumeList()
        
        detector.delegate = self
        detector.start()
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    @IBOutlet weak var refreshButton: NSButton!
    
    @IBAction func onRefresh(_ sender: Any) {
        refreshVolumeList()
    }
    
    
    func deviceAdded(_ device: io_object_t) {
    }
    
    func deviceRemoved(_ device: io_object_t) {
    }

    // 非同期のグループ作るよ！！！
    let dispatchGroup = DispatchGroup()
    // 並列で実行できるよ〜
    let dispatchQueue = DispatchQueue(label: "queue", attributes: .concurrent)
    
    @IBAction func onButtonAction(_ sender: Any) {
        
        if self.fileCount < 0 {
            let selectedIndex = volumeList.indexOfSelectedItem
            
            dispatchGroup.enter()
            dispatchQueue.async {
                self.startProcessForView(selectedIndex)
                
                self.writeFileAll(self.volumeArray[selectedIndex])
                if( self.isInterrupt != true ) {
                    self.verifyFileAll(self.volumeArray[selectedIndex])
                }
                self.deleteFileAll(self.volumeArray[selectedIndex])
                self.fileCount = -1
                self.isInterrupt = false
 
                self.dispatchGroup.leave()
                self.addLog("finished!!")
                self.addLog("")
            }
            dispatchGroup.notify(queue: .main) {
                self.finishProcessForView()
            }
            
        } else if self.isInterrupt == false {
            isInterrupt = true
            actionButton.isEnabled = false
            addLog("stop testing...")
        }
    }
    
    func startProcessForView(_ selectedIndex: Int) {
        DispatchQueue.main.async {
            self.volumeList.isEnabled = false
            self.actionButton.title = "Stop"
            self.indicator.floatValue = 0.0
            self.indicatorSub = Double(self.volumeArray[selectedIndex].freeBlock / (UInt64(self.MAX_FILE_SIZE)/self.volumeArray[selectedIndex].blockSize) * 2+1)
            self.indicator.maxValue = self.indicatorSub
        }
    }
    
    func finishProcessForView() {
        DispatchQueue.main.async {
            self.volumeList.isEnabled = true
            self.actionButton.isEnabled = true
            self.actionButton.title = "Start"
        }
    }
    
    func inclimentIndicatorValue() {
        DispatchQueue.main.async {
            self.indicatorSub -= 1.0
            self.indicator.doubleValue = self.indicator.maxValue-self.indicatorSub
        }
    }
    
    func addLog(_ text: String) {
        DispatchQueue.main.async {
            self.logText += text + "\n"
            self.logView.string = self.logText
        }
    }
    
    func clearLog() {
        logText = ""
        logView.string = logText
    }
    
    func removeOptionalString(_ str: String) -> String {
        var temp = str
        
        if let range = temp.range(of: "Optional(\"") {
            temp.removeSubrange(range)
        }
        if let range = temp.range(of: "\")") {
            temp.removeSubrange(range)
        }
        
        return temp
    }

    
    func addVolume(_ url: URL) -> Volume {
        var volume = Volume()
       
        if url.path.hasPrefix("/Volumes")/* || url.path == "/"*/ {

            let byteFormatter = ByteCountFormatter()
            byteFormatter.countStyle = .file
            
            if let capacities = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey, .volumeNameKey, .volumeLocalizedFormatDescriptionKey])
            {
                if let totalBytes = capacities.volumeTotalCapacity,
                    let availableBytes = capacities.volumeAvailableCapacity, totalBytes > 0
                {
                    let total = byteFormatter.string(fromByteCount: Int64(totalBytes))
                    let available = byteFormatter.string(fromByteCount: Int64(availableBytes))
                    let volumeName = removeOptionalString("\(String(describing: capacities.volumeName))")
                    let formatDescription = removeOptionalString("\(String(describing: capacities.volumeLocalizedFormatDescription))")

                    volume = Volume(url: url, volumeName: volumeName, dispString: volumeName + " : " + formatDescription + ", \(available) / \(total)")
                }
            }
        }
/*
         do {
            let volumeAttr = try FileManager.default.attributesOfFileSystem(forPath: "/Volume/" + name)
            
            addLog(volumeAttr[FileAttributeKey.systemSize] as! String)
            addLog(volumeAttr[FileAttributeKey.systemFreeSize] as! String)
        } catch {
        }
*/
        return volume
    }
    
    // マウントボリュームのリストを作り直す
    func refreshVolumeList() {
        
        addLog("search mounted volumes...")
       
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey, .volumeNameKey, .volumeLocalizedFormatDescriptionKey], options: [])!
        
        volumeArray.removeAll()
        for url in volumes {
            let volume = addVolume(url)
            if volume.isAvailable() {
                volumeArray.append(volume)
            
                addLog( volume.dispString )
            }
        }
        
        // 選択肢の再構成
        volumeList.removeAllItems()
        for volume in volumeArray {
            volumeList.addItem(withTitle: volume.dispString)
        }
        
/*
        let files = FileManager.default.enumerator(atPath: "/Volumes")
        while let file = files?.nextObject() {
            viewModel.addLog(file as! String)
        }
 */
    }
    
    var ramdomGenerator = SeededGenerator()         // シード指定可のランダムジェネレータ
    let MAX_FILE_SIZE = 2*1024*1024*1024/16    // 作成ファイルの最大サイズ
    
    // 乱数を使用してテンポラリのファイル名をフルパスで作成する
    func makeFilenameFromRandom(volume: Volume) -> String {
        var fileName = volume.path
            
        if fileName.hasSuffix("/") == false {
            fileName += "/"
        }
        fileName += String(UInt32.random(in: UInt32.min..<UInt32.max, using: &ramdomGenerator)|0xF0000000, radix: 16)
        fileName += ".tsm"

        return fileName
    }
    
    // ストレージの残りを見て最大ファイルサイズを計算する
    func calcMaxFileSize(volume: Volume) -> Int {
        // 空き領域の更新
        volume.upateFreeBlock()
        
        var fileSize = MAX_FILE_SIZE
        if volume.freeBlock*volume.blockSize < fileSize {
            fileSize = Int(volume.freeBlock*volume.blockSize)
        }
        
        return fileSize
    }

    // テンポラリファイルに書き出すデータの作成
    func createWriteData(initData: UInt64, size: Int) -> Data {
       var writeArray = [UInt64](repeating: initData, count: size/MemoryLayout<UInt64>.size)
// 要素ごとに乱数を入れると重すぎて死にます
/*
        writeArray.withUnsafeMutableBufferPointer { buffer in
            for i in 0..<MAKE_MAX_FILE_SIZE/MemoryLayout<UInt64>.size {
                buffer[i] = UInt64.random(in: UInt64.min...UInt64.max, using: &randomGenerator)
            }
        }
*/
        return Data(bytes: &writeArray, count: writeArray.count*MemoryLayout<UInt64>.size)
    }
    
    func writeFile(_ volume: Volume, count: Int) -> (time: TimeInterval, writeSize: Int) {
        ramdomGenerator = SeededGenerator(seed: UInt64(count))
        
        // ファイル名を先に作る
        let fileName = makeFilenameFromRandom(volume: volume)

        // make file size
        let fileSize = calcMaxFileSize(volume: volume)
        if fileSize <= 0 {
            return (0.0, 0)
        }
        
        // create write data
        let rnd = UInt64.random(in: UInt64.min...UInt64.max, using: &ramdomGenerator)
        let writeData = createWriteData(initData: rnd, size: fileSize)

        // ファイルがあったら削除
        if FileManager.default.fileExists(atPath: fileName) {
            do {
                try FileManager.default.removeItem(atPath: fileName)
                
            } catch {
                addLog("can't delete exists file (" + fileName + ")")
                return (0.0, 0)
            }

        }
        
        // get start time
        let startDate = Date()
        
        // create & write file
        let result = FileManager.default.createFile(atPath: fileName, contents: nil, attributes: nil)
        if result == true {
            let fh = FileHandle(forWritingAtPath: fileName)
            if fh != nil {
                fh?.write(writeData)
                fh?.closeFile()
                
                let dt = Date().timeIntervalSince(startDate)
                return (Double(fileSize)/dt/1000.0/1000.0, fileSize)
            }
        } else {
            addLog("can't create file: \(fileName)")
        }
        
        return (0.0, 0)
    }
    
    func writeFileAll(_ volume: Volume) {
        addLog("write files...")
        
        var totalWriteSize: Int = 0
        var averageWriteTime: Double = 0.0
        fileCount = 0
        repeat {
            let result = writeFile(volume, count: fileCount)
            if( result.time > 0.0) {
                fileCount += 1
                inclimentIndicatorValue()
                totalWriteSize += result.writeSize
                averageWriteTime = (averageWriteTime + result.time)/2.0
            } else {
                break
            }
        } while( isInterrupt == false )
        
        addLog("total write size: \(totalWriteSize) Bytes")
        addLog("write time: \(round(averageWriteTime*10)/10) MB/s" )
    }
    
    func verifyFile(_ volume: Volume, count: Int) -> (time: TimeInterval, readSize: Int) {
        ramdomGenerator = SeededGenerator(seed: UInt64(count))
        
        // ファイル名を先に作る
        let fileName = makeFilenameFromRandom(volume: volume)
  
        // create compare data
        let compareData = UInt64.random(in: UInt64.min...UInt64.max, using: &ramdomGenerator)
        
        let fh: FileHandle = FileHandle(forReadingAtPath: fileName)!
        
        // 開始時間の取得
        let startDate = Date()
        
        var readData: Data = fh.readDataToEndOfFile()
        fh.closeFile()
        
        var dt = Date().timeIntervalSince(startDate)
        dt = Double(readData.count)/dt/1000/1000

        // メモリデータの比較
        let size: Int = readData.withUnsafeBytes { (rptr: UnsafePointer<UInt64>) -> Int in
            var i: Int = 0
            while i < readData.count/MemoryLayout<UInt64>.size {
                if     rptr[i+0]  != compareData
                    || rptr[i+1]  != compareData
                    || rptr[i+2]  != compareData
                    || rptr[i+3]  != compareData
                    || rptr[i+4]  != compareData
                    || rptr[i+5]  != compareData
                    || rptr[i+6]  != compareData
                    || rptr[i+7]  != compareData
                    || rptr[i+8]  != compareData
                    || rptr[i+9]  != compareData
                    || rptr[i+10] != compareData
                    || rptr[i+11] != compareData
                    || rptr[i+12] != compareData
                    || rptr[i+13] != compareData
                    || rptr[i+14] != compareData
                    || rptr[i+15] != compareData
                {
                    return i*MemoryLayout<UInt64>.size
                }
                i += 16
            }
            
            return readData.count
        }
        if size < readData.count {
            
            readData = Data()
            return (0.0, size)
        }
        
        readData = Data()
        return (dt, size)
    }
    
    func verifyFileAll(_ volume: Volume) {
        addLog("veryfy files...")
        
        var totalReadSize: Int = 0
        var averageReadTime: Double = 0.0
        for i in 0..<fileCount {
            if( isInterrupt == true ) {
                break   // 中止
            }
            let result = verifyFile(volume, count: i)
            totalReadSize += result.readSize
            inclimentIndicatorValue()
            if result.time <= 0.0 {
                break   // エラー
            } else {
                averageReadTime = (averageReadTime + result.time)/2.0
            }
        }
        addLog("total read size: \(totalReadSize) Bytes")
        addLog("read time: \(round(averageReadTime*10)/10) MB/s" )
    }
    
    func deleteFile(_ volume: Volume, count: Int) -> String {
        ramdomGenerator = SeededGenerator(seed: UInt64(count))
        
        let fileName = makeFilenameFromRandom(volume: volume)

        do {
            try FileManager.default.removeItem(atPath: fileName)
            
        } catch {
            return fileName
        }

        return ""
    }
    
    func deleteFileAll(_ volume: Volume) {
        addLog("delete files...")
        
        for i in 0..<fileCount {
            let result = deleteFile(volume, count: i)
            if result != "" {
                addLog("can't delete file: \(result)")
            }
        }
        inclimentIndicatorValue()
    }
}

