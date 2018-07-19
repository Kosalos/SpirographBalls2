import UIKit
import Metal

class Ribbon {
    let MAX_RIBBON:Int = 4000
    var data:[TVertex] = []
    var vertexBuffer: MTLBuffer?
    var index:Int = 0
    var isFull:Bool = false
    
    init() {
        for i in 0 ..< MAX_RIBBON {
            data.append(TVertex())
            data[i].drawStyle = 1
            data[i].color = float4(1,0.5,0,1);
        }
        
        reset()
    }
    
    func reset() {
        isFull = false
        index = 0
        oldP1 = float3()
        oldP2 = float3()
    }
    
    var oldRalpha:Float = 0
    var oldP1 = float3()    // memory of last pair of points. don't add to ribbon if not moving
    var oldP2 = float3()
    var np1 = float3()      // rolling memory of previous points for normal calc
    var np2 = float3()

    func addStrip(_ p1:float3, _ p2:float3) {
        func addPoint(_ pt:float3) {
            data[index].pos = pt
            
            let p2 = pt - np1
            let p3 = pt - np2
            data[index].nrm = normalize(cross(p2,p3))
            np1 = np2
            np2 =  pt

            let np = normalize(data[index].pos)
            data[index].txt.x = np.x
            data[index].txt.y = np.y
            
            index += 1
            if index >= MAX_RIBBON {
                index = 0
                isFull = true
            }
        }

        if length(p1 - oldP1) < 0.01 && length(p2 - oldP2) < 0.01 { return }
        
        addPoint(p1)
        addPoint(p2)
        oldP1 = p1
        oldP2 = p2
        
        // ------------------------------
        if fabs(oldRalpha - vc.ribbonAlpha) > 0.01 {
            oldRalpha = vc.ribbonAlpha
            
            for i in 0 ..< MAX_RIBBON {
                data[i].color = float4(1,1,1,oldRalpha)
            }
        }
    }

    //MARK: -
    // draw full data as two sections so that triangle strip erases tail end correctly. (TODO: get rid of the gap between sections)
    
    func render(_ renderEncoder:MTLRenderCommandEncoder) {
        if !isFull && index < 4 { return }
        
        vertexBuffer = gDevice.makeBuffer(bytes:data, length: MAX_RIBBON * MemoryLayout<TVertex>.stride, options: MTLResourceOptions())
        
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: index)

        if isFull {
            renderEncoder.setVertexBuffer(vertexBuffer, offset: index * MemoryLayout<TVertex>.stride, index: 0)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: MAX_RIBBON - index)
        }
    }
}
