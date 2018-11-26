import UIKit
import Metal
import MetalKit
import simd

var vc:ViewController! = nil
var constantData = ConstantData()
var spheres:[Sphere] = []
var ribbon = Ribbon()

let numSpheres:Int = 4

class ViewController: UIViewController, WGDelegate {
    var rendererL: Renderer!
    var rendererR: Renderer!
    var controlBuffer:MTLBuffer! = nil
    
    var isStereo:Bool = false
    var ribbonWidth:Float = 0.2
    var sphereAlpha:Float = 1
    var ribbonAlpha:Float = 1
    var drawStyle:Int = 1
    var xAxisOnly:Bool = false
    var center = CGPoint()
    
    @IBOutlet var d3ViewL: MTKView!
    @IBOutlet var d3ViewR: MTKView!
    @IBOutlet var wg: WidgetGroup!
    
    //MARK: -
    
    override func viewDidLoad() {
        super.viewDidLoad()
        vc = self
        gDevice = MTLCreateSystemDefaultDevice()
        d3ViewL.device = gDevice
        d3ViewR.device = gDevice
        
        guard let newRenderer = Renderer(metalKitView: d3ViewL, 0) else { fatalError("Renderer cannot be initialized") }
        rendererL = newRenderer
        rendererL.mtkView(d3ViewL, drawableSizeWillChange: d3ViewL.drawableSize)
        d3ViewL.delegate = rendererL
        
        guard let newRenderer2 = Renderer(metalKitView: d3ViewR, 1) else { fatalError("Renderer cannot be initialized") }
        rendererR = newRenderer2
        rendererR.mtkView(d3ViewR, drawableSizeWillChange: d3ViewR.drawableSize)
        d3ViewR.delegate = rendererR
        
        for i in 0 ... numSpheres { spheres.append(Sphere(i)) }
        
        reset()
        initializeWidgetGroup()
        layoutViews()
        
        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(self.swipeWgGesture(gesture:)))
        swipeUp.direction = .up
        wg.addGestureRecognizer(swipeUp)
        
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(self.swipeWgGesture(gesture:)))
        swipeDown.direction = .down
        wg.addGestureRecognizer(swipeDown)
        
        Timer.scheduledTimer(withTimeInterval:0.05, repeats:true) { timer in self.timerHandler() }
    }
    
    //MARK: -
    
    func initializeWidgetGroup() {
        wg.delegate = self
        wg.initialize()
        
        func sphereGroup(_ i:Int) { // base 1
            let rRange:Float = 0.4
            wg.addLegend(String(format:"Sphere %d",i))
            wg.addDualFloat(&spheres[i].rotX,&spheres[i].rotY, -rRange,rRange,rRange/10,"Rotate")
            wg.addSingleFloat(&spheres[i].radius, 0.2,3.0,0.5,"Radius",.radius)
            wg.addLine()
        }
        
        wg.addCommand("Reset",.reset)
        wg.addLine()
        wg.addCommand("Restart",.clear)
        wg.addLine()
        
        for i in 1 ... numSpheres { sphereGroup(i) }
        
        wg.addLegend("Ribbon")
        wg.addSingleFloat(&ribbonWidth, 0.01,2,0.1, "Width")
        wg.addSingleFloat(&ribbonAlpha, 0.01,1,0.1, "Alpha")
        wg.addLine()
        wg.addLegend("Sphere")
        wg.addCommand("Style",.style)
        wg.addSingleFloat(&sphereAlpha, 0.00,1,0.1, "Alpha")
        wg.addLine()
        wg.addCommand("New Skin",.skin)
        wg.addLine()
        wg.addCommand("Xaxis Only",.xOnly)
        wg.addLine()
        wg.addCommand("Harmonize",.pi)
        wg.addLine()
        wg.addCommand("Stereo",.stereo)
        wg.addLine()
        wg.addCommand("Help",.help)
        wg.addLine()
    }
    
    //MARK: -
    
    func layoutViews() {
        var xBase = CGFloat()
        let WgWidth:CGFloat = 120
        
        if !wg.isHidden {
            xBase = WgWidth
            wg.frame = CGRect(x:0, y:0, width:WgWidth, height:view.bounds.height)
        }
        
        var vr = CGRect(x:xBase, y:0, width:view.bounds.width-xBase, height:view.bounds.height)
        d3ViewL.frame = vr
        
        if isStereo {
            vr.size.width /= 2
            d3ViewL.frame = vr
            
            d3ViewR.isHidden = false
            vr.origin.x += vr.width
            d3ViewR.frame = vr
        }
        else {
            d3ViewR.isHidden = true
        }
        
        let hk = d3ViewL.bounds
        arcBall.initialize(Float(hk.size.width),Float(hk.size.height))
        
        center.x = hk.width/2    // used by rotate()
        center.y = hk.height/2
    }
    
    //MARK: -
    
    @objc func timerHandler() {
        
        if radiusIndex == NONE {
            for s in spheres { s.update() }
            _ = wg.update()
            
            // ribbon edge centered on last sphere, along a line that connects it to the previous sphere
            let base = spheres[numSpheres-1].center // 2nd to last sphere
            let end = spheres[numSpheres].center  // last sphere
            let diff = end - base
            let p1 = base + diff * (1.0 - ribbonWidth)
            let p2 = base + diff * (1.0 + ribbonWidth)
            ribbon.addStrip(p1,p2)
            
            rotate(paceRotate.x,paceRotate.y)
        }
        else {
            for s in spheres { s.generate() }
            _ = wg.update()
        }
    }
    
    //MARK: -
    
    func reset() {
        stopRotation()
        arcBall.reset()
        ribbon.reset()
        
        for i in 1 ... numSpheres {
            spheres[i].reset()
            spheres[i].setRadius(0.7 - Float(i) * 0.1)
        }
        
        wg.setNeedsDisplay()
    }
    
    //MARK: -
    
    func wgCommand(_ cmd:CmdIdent) {
        switch(cmd) {
        case .stereo :
            isStereo = !isStereo
            layoutViews()
            
        case .clear :
            ribbon.reset()
            
        case .reset :
            reset()
            
        case .xOnly :
            xAxisOnly = !xAxisOnly
            if xAxisOnly {
                for i in 1 ... numSpheres { spheres[i].rotY = 0;  }
                ribbon.reset()
            }
            
        case .style :
            drawStyle = 1 - drawStyle
            for i in 0 ... numSpheres { spheres[i].setDrawStyle(drawStyle) }
            
        case .pi :
            func harmonize(_ v:Float) -> Float { // intent is that rotations are increments of pi / 60
                if v == 0 { return 0 }
                let v1:Float = Float.pi / 60.0
                let v2 = Int(v1 * 100000)
                let v3 = Int(v  * 100000)
                let v4:Int = Int(v3 / v2) * v2
                let ans = Float(v4) / 100000.0
                return ans
            }
            
            for i in 1 ... numSpheres {
                spheres[i].rotX = harmonize(spheres[i].rotX)
                spheres[i].rotY = harmonize(spheres[i].rotY)
            }
            ribbon.reset()
            
        case .skin :
            tIndex1 = Int(arc4random() % 7)
            tIndex2 = Int(arc4random() % 7)
            
        case .help : performSegue(withIdentifier: "helpSegue", sender: self)
            
        case .radius :
            radiusIndex = 1 + (wg.focus - 6)/4   // kludge to get sphere index from control panel ( base 1 )
        default : break
        }
        
        wg.setNeedsDisplay()
    }
    
    func wgGetString(_ index:Int) -> String { return "unused" }
    func wgGetColor(_ index:Int) -> UIColor { return .white }
    func wgRefresh() {}
    func wgAlterPosition(_ dx:Float, _ dy:Float) {}
    
    //MARK: -
    
    var radiusIndex:Int = NONE
    
    func radiusChangedCallback() {
        if radiusIndex != NONE {
            let ratio:Float = pow(spheres[radiusIndex].oldRadius,2) / pow(spheres[radiusIndex].radius,2)
            spheres[radiusIndex].oldRadius = spheres[radiusIndex].radius
            
            spheres[radiusIndex].rotX *= ratio
            spheres[radiusIndex].rotY *= ratio
            
            radiusIndex = NONE
            ribbon.reset()
        }
    }
    
    //MARK: -
    
    var tIndex1:Int = 0  // random texture indices
    var tIndex2:Int = 2
    var isBusy:Bool = false
    
    func render(_ renderEncoder:MTLRenderCommandEncoder) {
        if isBusy { return }
        isBusy = true
        
        if sphereAlpha > 0 {
            renderEncoder.setFragmentTexture(textures[tIndex1], index:0)
            for s in spheres { s.render(renderEncoder) }
        }
        
        renderEncoder.setFragmentTexture(textures[tIndex2], index:0)
        ribbon.render(renderEncoder)
        
        isBusy = false
    }
    
    //MARK:-
    
    var oldPt = CGPoint()
    
    @IBAction func panGesture(_ sender: UIPanGestureRecognizer) { // alter focused widget values
        var pt = sender.translation(in: self.view)
        
        switch sender.state {
        case .began :
            oldPt = pt
        case .changed :
            pt.x -= oldPt.x
            pt.y -= oldPt.y
            wg.focusMovement(pt)
        case .ended :
            radiusChangedCallback()
            pt.x = 0
            pt.y = 0
            wg.focusMovement(pt)
        default : break
        }
    }
    
    @objc func swipeWgGesture(gesture: UISwipeGestureRecognizer) -> Void {
        switch gesture.direction {
        case .up : wg.moveFocus(-1)
        case .down : wg.moveFocus(+1)
        default : break
        }
    }
    
    //MARK:-
    
    var paceRotate = CGPoint()
    
    func rotate(_ x:CGFloat, _ y:CGFloat) {
        arcBall.mouseDown(center)
        arcBall.mouseMove(CGPoint(x: center.x - x, y: center.y - y))
    }
    
    @IBAction func pan2Gesture(_ sender: UIPanGestureRecognizer) { // rotate 3D image
        let pt = sender.translation(in: self.view)
        let scale:CGFloat = 0.05
        paceRotate.x = pt.x * scale
        paceRotate.y = pt.y * scale
    }
    
    @IBAction func pinchGesture(_ sender: UIPinchGestureRecognizer) {
        let min:Float = 1       // close
        let max:Float = 1000    // far
        
        translationAmount *= Float(1 + (1 - sender.scale) / 10 )
        if translationAmount < min { translationAmount = min }
        if translationAmount > max { translationAmount = max }
    }
    
    //MARK:-
    
    func stopRotation() {
        paceRotate.x = 0
        paceRotate.y = 0
    }
    
    @IBAction func tapGesture(_ sender: UITapGestureRecognizer) { stopRotation() }
    
    @IBAction func tap2Gesture(_ sender: UITapGestureRecognizer) {
        wg.isHidden = !wg.isHidden
        layoutViews()
    }
    
    override var prefersStatusBarHidden: Bool { return true }
}

// MARK:

func drawLine(_ context:CGContext, _ p1:CGPoint, _ p2:CGPoint) {
    context.beginPath()
    context.move(to:p1)
    context.addLine(to:p2)
    context.strokePath()
}

func drawVLine(_ context:CGContext, _ x:CGFloat, _ y1:CGFloat, _ y2:CGFloat) { drawLine(context,CGPoint(x:x,y:y1),CGPoint(x:x,y:y2)) }
func drawHLine(_ context:CGContext, _ x1:CGFloat, _ x2:CGFloat, _ y:CGFloat) { drawLine(context,CGPoint(x:x1, y:y),CGPoint(x: x2, y:y)) }

//MARK:-

var fntSize:CGFloat = 0
var txtColor:UIColor = .clear
var textFontAttributes:NSDictionary! = nil

func drawText(_ x:CGFloat, _ y:CGFloat, _ color:UIColor, _ sz:CGFloat, _ str:String) {
    if sz != fntSize || color != txtColor {
        fntSize = sz
        txtColor = color
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = NSTextAlignment.left
        let font = UIFont.init(name: "Helvetica", size:sz)!
        
        textFontAttributes = [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: color,
            NSAttributedString.Key.paragraphStyle: paraStyle,
        ]
    }
    
    str.draw(in: CGRect(x:x, y:y, width:800, height:100), withAttributes: textFontAttributes as? [NSAttributedString.Key : Any])
}
