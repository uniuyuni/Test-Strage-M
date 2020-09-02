//
//  ViewController.swift
//  Test Strage M
//
//  Created by うに on 2020/08/25.
//  Copyright © 2020 うに. All rights reserved.
//

import Cocoa

let MAX_FILE_SIZE: Int = 2*1024*1024*1024/16    // 作成ファイルの最大サイズ


class ViewController: NSViewController, USBDetectorDelegate {

    @IBOutlet weak var volumeList: NSPopUpButton!
    @IBOutlet weak var refreshButton: NSButton!
    @IBOutlet weak var actionButton: NSButton!
    @IBOutlet weak var indicator: NSLevelIndicator!
    @IBOutlet weak var logView: NSTextView!
    @IBOutlet weak var dontDeleteFilesCheck: NSButton!
    @IBOutlet weak var deleteButton: NSButton!
    @IBOutlet weak var stateText: NSTextField!
    @IBOutlet weak var verifyButton: NSButton!
    
    typealias StatFS = statfs // this does the trick

    // マウントされているボリュームの情報
    class Volume {
        
        init() {
            
        }
        
        init( url: URL, volumeName: String, dispString: String ) {
            var fs: StatFS = StatFS()
            if statfs(url.path, &fs) == 0 {
                self.url = url
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
            if statfs(self.url.path, &fs) == 0 {
                self.freeBlock = fs.f_bfree
            }
        }
        
        func isAvailable() -> Bool {
            return self.blocks > 0
        }
        
        var url: URL = URL(fileURLWithPath: "/")
        var name: String = ""
        var blockSize: UInt64 = 0
        var blocks: UInt64 = 0
        var freeBlock: UInt64 = 0
        var dispString: String = ""
    }
    
    class File {
        
        var url: URL            // ファイル名を含んだurl
        var fileName: String    // ファイル名のみ
        var data: Data          // 読み込んだファイル

        init(_ url: URL, _ fileName: String) {
            data = Data()
            self.url = url
            self.fileName = fileName
            self.url.appendPathComponent(fileName)
        }
        
        func exists() -> Bool {
            
            return FileManager.default.fileExists(atPath: url.path)
        }
        
        func create() -> Bool {
            return FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
        }
        
        func delete() -> Bool {
            do {
                try FileManager.default.removeItem(atPath: url.path)
            
            } catch {
                return false
            }
            
            return true
        }
                
        func read() -> Bool {
            do {
                data = try Data(contentsOf: url)
                
            } catch {
                return false
            }

            return true
        }
        
        func write(_ data: Data) -> Bool {
            do {
                try data.write(to: url)
            } catch {
                return false
            }
            self.data = data
            return true
        }
        
        func getFirstSectorNumber() -> UInt64 {
            let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
            
            return 0
        }
    }
    
    var logText: String = ""        // ログテキスト
    var volumeArray: Array<Volume> = Array()    // ストレージの情報配列
    var isInterrupt: Bool = false   // 強制終了フラグ
    var indicatorSub: Double = 0.0  // インジケーター逆カウンタ
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
    
    
    @IBAction func onRefresh(_ sender: Any) {
        refreshVolumeList()
    }
    
    
    func countWriteFiles(_ volume: Volume) -> Int {
        // 存在するファイルの数を数える
        var fileCount: Int = 0
        repeat {
            let file = File(volume.url, makeFilenameFromCount(fileCount))
            if file.exists() == false {
                break
            }
            fileCount += 1
        } while( true )
        
        return fileCount
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
        
        // ファイルカウンタがマイナスなら最初から
        if self.actionButton.title == "Start" {
            
            // 選択されたボリューム
            let selectedIndex = volumeList.indexOfSelectedItem

            startProcessForView(selectedIndex)
            
            dispatchGroup.enter()
            dispatchQueue.async {
                
                let fileCount: Int = self.writeFileAll(self.volumeArray[selectedIndex])
                if( self.isInterrupt != true ) {
                    self.verifyFileAll(self.volumeArray[selectedIndex], fileCount: fileCount)
                }
                if self.dontDeleteFilesCheck.state == NSControl.StateValue.off {
                    self.deleteFileAll(self.volumeArray[selectedIndex], fileCount: fileCount)
                } else {
                    self.inclimentIndicatorValue()
                }
                self.finishIndicatorValue()
                self.isInterrupt = false
 
                self.dispatchGroup.leave()
                self.addLog("finished!!")
                self.addLog("")
            }
            dispatchGroup.notify(queue: .main) {
                self.finishProcessForView()
            }

        // 中断
        } else {
            isInterrupt = true
            actionButton.isEnabled = false
            addLog("stop testing...")
        }
    }
    
    @IBAction func onDeleteFiles(_ sender: Any) {
        // 選択されたボリューム
        let selectedIndex = volumeList.indexOfSelectedItem

        // 存在するファイルの数を数える
        let fileCount: Int = countWriteFiles(volumeArray[selectedIndex])

        // 見つけたファイルだけ削除
        deleteFileAll(self.volumeArray[selectedIndex], fileCount: fileCount)
        addLog("finished!!")
        addLog("")
    }
    
    @IBAction func onVerifyFiles(_ sender: Any) {
        // 選択されたボリューム
        let selectedIndex = volumeList.indexOfSelectedItem
        
        startProcessForView(selectedIndex, indicatorMul: 1)
        
        dispatchGroup.enter()
        dispatchQueue.async {
            // 存在するファイルの数を数える
            let fileCount: Int = self.countWriteFiles(self.volumeArray[selectedIndex])
            
            self.verifyFileAll(self.volumeArray[selectedIndex], fileCount: fileCount)
            self.finishIndicatorValue()
            self.isInterrupt = false

            self.dispatchGroup.leave()
            self.addLog("finished!!")
            self.addLog("")
       }
       dispatchGroup.notify(queue: .main) {
           self.finishProcessForView()
       }
    }

    func startProcessForView(_ selectedIndex: Int, indicatorMul: Double = 2) {
        self.volumeList.isEnabled = false
        self.actionButton.title = "Stop"
        self.deleteButton.isEnabled = false
        self.verifyButton.isEnabled = false
        self.refreshButton.isEnabled = false
        self.indicator.floatValue = 0.0
        self.indicatorSub = ceil(Double(self.volumeArray[selectedIndex].freeBlock) / Double(UInt64(MAX_FILE_SIZE)/self.volumeArray[selectedIndex].blockSize)) * indicatorMul+1
        self.indicator.maxValue = self.indicatorSub
    }
    
    func finishProcessForView() {
        DispatchQueue.main.async {
            self.volumeList.isEnabled = true
            self.actionButton.isEnabled = true
            self.actionButton.title = "Start"
            self.deleteButton.isEnabled = true
            self.verifyButton.isEnabled = true
            self.refreshButton.isEnabled = true
        }
    }
    
    func setStateText(process: String, totalSize: Int, time: TimeInterval, count: Int) {
        DispatchQueue.main.async {
            self.stateText.stringValue = process + ": " + "\(toStringCanmaFormat(totalSize)) Byte, " + "\(round(time*10)/10) MB/s"
        }
    }
    
    func inclimentIndicatorValue() {
        DispatchQueue.main.async {
            self.indicatorSub -= 1.0
            self.indicator.doubleValue = self.indicator.maxValue-self.indicatorSub
        }
    }
    func finishIndicatorValue() {
        DispatchQueue.main.async {
            self.indicatorSub = 0
            self.indicator.doubleValue = self.indicator.maxValue
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
        
        // 開始可能か？
        let isAction = volumeArray.count > 0
        actionButton.isEnabled = isAction
        deleteButton.isEnabled = isAction
        verifyButton.isEnabled = isAction

/*
        let files = FileManager.default.enumerator(atPath: "/Volumes")
        while let file = files?.nextObject() {
            viewModel.addLog(file as! String)
        }
 */
    }
    
    var ramdomGenerator = SeededGenerator()    // シード指定可のランダムジェネレータ
    
    // 乱数を使用してテンポラリのファイル名をフルパスで作成する
    func makeFilenameFromCount(_ count: Int) -> String {
/*
        var fileName: String = volume.path
            
        if fileName.hasSuffix("/") == false {
            fileName += "/"
        }
        fileName += String(format: "%08X", count) + ".tsm"
 */

        return String(format: "%08d", count) + ".tsm"
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
            for i in 0..<size/MemoryLayout<UInt64>.size {
                buffer[i] = UInt64.random(in: UInt64.min...UInt64.max, using: &randomGenerator)
            }
        }
*/
        return Data(bytes: &writeArray, count: writeArray.count*MemoryLayout<UInt64>.size)
    }
    
    func deleteExistsFile(_ file: File) -> Bool {
        if file.exists() == true {
            return file.delete()
        }
        return true
    }
    
    func writeFile(_ volume: Volume, count: Int) -> (time: TimeInterval, writeSize: Int) {
        ramdomGenerator = SeededGenerator(seed: UInt64(count))
        
        // ファイルを先に作る
        let file = File(volume.url, makeFilenameFromCount(count))

        // make file size
        let fileSize = calcMaxFileSize(volume: volume)
        if fileSize <= 0 {
            return (0.0, 0)
        }
        
        // create write data
        let rnd = UInt64.random(in: UInt64.min...UInt64.max, using: &ramdomGenerator)
        let writeData = createWriteData(initData: rnd, size: fileSize)

        // ファイルがあったらスキップ
        if file.exists() {
            return (Double(fileSize)/1000.0/1000.0, fileSize)
        }
/*
        // ファイルがあったら削除
        if deleteExistsFile(file) == false {
            addLog("can't delete exists file (" + fileName + ")")
            return (0.0, 0)
        }
 */
        // get start time
        let startDate = Date()
        
        // create & write file
        if file.create() == true {
            if file.write(writeData) == false {
                addLog("write file error! \(file.fileName)")
                file.delete()
                return (0.0, 0)
            }
            let dt = Date().timeIntervalSince(startDate)
            return (Double(fileSize)/dt/1000.0/1000.0, fileSize)

        } else {
            addLog("can't create file: \(file.fileName)")
        }
        
        return (0.0, 0)
    }
    
    func writeFileAll(_ volume: Volume) -> Int {
        addLog("write files...")
        
        var totalWriteSize: Int = 0
        var averageWriteTime: Double = 0.0
        var fileCount: Int = 0
        repeat {
            let result = writeFile(volume, count: fileCount)
            if( result.time > 0.0) {
                fileCount += 1
                inclimentIndicatorValue()
                totalWriteSize += result.writeSize
                averageWriteTime = (averageWriteTime + result.time)/2.0
                setStateText( process: "write bytes", totalSize: totalWriteSize, time: result.time, count: fileCount)
            } else {
                break
            }
        } while( isInterrupt == false )
        
        addLog("total write size: \(toStringCanmaFormat(totalWriteSize)) Byte")
        addLog("write file time: \(round(averageWriteTime*10)/10) MB/s" )
        
        return fileCount
    }
    
    func verifyFile(_ volume: Volume, count: Int) -> (time: TimeInterval, verifySize: Int) {
        
        ramdomGenerator = SeededGenerator(seed: UInt64(count))
        
        // ファイルを先に作る
        let file = File(volume.url, makeFilenameFromCount(count))
  
        // create compare data
        let compareData = UInt64.random(in: UInt64.min...UInt64.max, using: &ramdomGenerator)
        
        // 開始時間の取得
        let startDate = Date()

        let result = autoreleasepool { () -> (Double, Int) in // コレないとメモリプールが溜まって死亡
            if file.read() == false {
                addLog("read file error! \(file.fileName)")
                return (0.0, 0)
            }

            var dt = Date().timeIntervalSince(startDate)
            dt = Double(file.data.count)/dt/1000/1000

            // メモリデータの比較
            let size: Int = file.data.withUnsafeBytes { (rptr: UnsafePointer<UInt64>) -> Int in
                var i: Int = 0
                while i < file.data.count/MemoryLayout<UInt64>.size {
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
                        return file.data.count-i*MemoryLayout<UInt64>.size
                    }
                    i += 16
                }
                
                return file.data.count
            }
            if size < file.data.count {
                addLog("verify file error! \(file.fileName)")
                return (dt, -file.data.count)
            }

            return (dt, file.data.count)
        }
        return result
    }
    
    func verifyFileAll(_ volume: Volume, fileCount: Int) {
        addLog("veryfy files...")
        
        var totalVerifySize: Int = 0
        var totalErrorSize: Int = 0
        var averageReadTime: Double = 0.0
        for i in 0..<fileCount {
            if( isInterrupt == true ) {
                break   // 中止
            }
            let result = verifyFile(volume, count: i)
            inclimentIndicatorValue()
            if result.time <= 0.0 {
                // 読み込みエラー
            } else {
                if result.verifySize <= 0 {
                    // 比較エラー
                    totalErrorSize += -result.verifySize
                    setStateText( process: "verify failure bytes", totalSize: totalErrorSize, time: result.time, count: i)
                } else {
                    totalVerifySize += result.verifySize
                    setStateText( process: "verify success bytes", totalSize: totalVerifySize, time: result.time, count: i)
                }
            }
            averageReadTime = (averageReadTime + result.time)/2.0
        }
        addLog("total verify success size: \(toStringCanmaFormat(totalVerifySize)) Byte")
        addLog("total verify failure size: \(toStringCanmaFormat(totalErrorSize)) Byte")
        addLog("read file time: \(round(averageReadTime*10)/10) MB/s" )
    }
    
    func deleteFile(_ volume: Volume, count: Int) -> String {
        let file = File(volume.url, makeFilenameFromCount(count))

        if file.delete() == false {
            return file.fileName
        }

        return ""
    }
    
    func deleteFileAll(_ volume: Volume, fileCount: Int) {
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

