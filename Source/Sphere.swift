import Metal

private var unitSphereVData = Array<TVertex>()    // vertices
private var unitSphereIDataL = Array<UInt16>()    // indices of line segments
private var unitSphereIDataT = Array<UInt16>()    // indices of triangles
private var iBufferL: MTLBuffer?
private var iBufferT: MTLBuffer?

class Sphere {
    var index:Int = 0
    var vBuffer: MTLBuffer?
    var vData = Array<TVertex>()
    var radius:Float = 1
    var oldRadius:Float = 1
    var center:float3 = float3()
    var color:float4 = float4(1,1,1,1)
    var drawStyle:UInt8 = 1
    var rotX:Float = 0
    var rotY:Float = 0
    var angleX:Float = 0
    var angleY:Float = 0
    let pi2:Float = Float.pi * 2.0
    
    init(_ nIndex:Int) {
        index = nIndex
        if unitSphereVData.count == 0 { generateUnitSphere() }
        for i in 0 ..< unitSphereVData.count {
            vData.append(unitSphereVData[i])
        }
        
        generate()
    }
    
    func reset() {
        rotX = 0
        rotY = 0
        angleX = 0
        angleY = 0
    }
    
    func update() {
        angleX += rotX
        angleY += rotY
        generate()
    }

    func setRadius(_ nradius:Float) {
        radius = nradius
        oldRadius = nradius
        generate()
    }
    
    func setDrawStyle(_ ds:Int) {
        for i in 0 ..< vData.count { unitSphereVData[i].drawStyle = UInt8(ds) }
    }
    
    //MARK: -
    
    func rotateX(_ pos:float3, _ angle:Float) -> float3 {
        let ss = sinf(angle)
        let cc = cosf(angle)
        var ans:float3 = pos
        ans.x = pos.x * cc - pos.y * ss
        ans.y = pos.x * ss + pos.y * cc
        return ans
    }
    
    func rotateY(_ pos:float3, _ angle:Float) -> float3 {
        let ss = sinf(angle)
        let cc = cosf(angle)
        var ans:float3 = pos
        ans.z = pos.z * cc - pos.y * ss
        ans.y = pos.z * ss + pos.y * cc
        return ans
    }
    
    var oldSalpha:Float = 0

    func generate() {
        if abs(oldSalpha - vc.sphereAlpha) > 0.01 {
            oldSalpha = vc.sphereAlpha
            for i in 0 ..< vData.count { unitSphereVData[i].color = float4(1,1,1,oldSalpha) }
        }

        let size:Int = unitSphereVData.count * MemoryLayout<TVertex>.stride

        if vBuffer == nil { vBuffer = gDevice?.makeBuffer(length:size, options:.storageModeShared) }

        if index == 0 {
            vBuffer?.contents().copyMemory(from:&unitSphereVData, byteCount:size)
            return
        }
        
        var localCenter:float3 = float3(0,spheres[index-1].radius + radius,0)
        let spinRatio = (radius * radius) / (spheres[index-1].radius * spheres[index-1].radius)
        localCenter = rotateX(localCenter,angleX * spinRatio)
        localCenter = rotateY(localCenter,angleY * spinRatio)

        center = spheres[index-1].center + localCenter
        
        for i in 0 ..< vData.count {
            vData[i].pos = rotateX(unitSphereVData[i].pos * radius,angleX)
            vData[i].pos = rotateY(vData[i].pos,angleY)
            vData[i].pos += center
            vData[i].color = float4(1,1,1,vc.sphereAlpha)
            vData[i].drawStyle = UInt8(vc.drawStyle)
        }
        
        vBuffer?.contents().copyMemory(from:&vData, byteCount:size)
    }
    
    //MARK: -

    func generateUnitSphere() {
        let nLat:Int = 20
        let nLong:Int = 20
        let nPitch = nLong + 1
        let pitchInc = Float(Double.pi) / Float(nPitch)
        let rotInc = Float(Double.pi * 2) / Float(nLat)
        
        for p in 1 ..< nPitch {
            let out = abs(radius * sinf(Float(p) * pitchInc))
            let y = radius * cosf(Float(p) * pitchInc)
            var fs:Float = 0
            for i in 0 ..< nLat {
                let model:float3 = float3(out * cosf(fs),y,out * sin(fs))
                var v = TVertex(center + model,float4(1))
                v.nrm = normalize(model)
                v.txt.x = Float(i) / Float(nLat-1)
                v.txt.y = Float(p) / Float(nPitch)
                v.drawStyle = drawStyle
                unitSphereVData.append(v)
                fs += rotInc
            }
        }
        
        // top, bottom
        var v = TVertex(float3(center.x, center.y+radius, center.z),color)
        v.nrm = normalize(float3(0,radius,0))
        v.drawStyle = drawStyle
        unitSphereVData.append(v)
        v = TVertex(float3(center.x, center.y-radius, center.z),color)
        v.nrm = normalize(float3(0,-radius,0))
        v.drawStyle = drawStyle
        unitSphereVData.append(v)
        
        let topIndex = UInt16(unitSphereVData.count - 2)
        
        // Line indices ------------------------------
        for p in 0 ..< nPitch-1 {
            let p2 = p * nLat
            for s in 0 ..< nLat {
                var s2 = s+1; if s2 == nLat { s2 = 0 }
                unitSphereIDataL.append(UInt16(p2 + s))
                unitSphereIDataL.append(UInt16(p2 + s2))
                
                if p < nPitch-2 {
                    unitSphereIDataL.append(UInt16(p2 + s))
                    unitSphereIDataL.append(UInt16(p2 + nLat + s))
                }
            }
        }
        
        for s in 0 ..< nLat {
            unitSphereIDataL.append(UInt16(s))
            unitSphereIDataL.append(topIndex)
            unitSphereIDataL.append(UInt16((nPitch-2)*nLat + s ))
            unitSphereIDataL.append(topIndex+1)
        }
        
        // Triangle indices ------------------------------
        for p in 0 ..< nPitch-2 {
            let p2 = p * nLat
            for s in 0 ..< nLat {
                var s2 = s+1; if s2 == nLat { s2 = 0 }
                let i1 = UInt16(p2 + s)
                let i2 = UInt16(p2 + s2)
                let i3 = i2 + UInt16(nLat)
                let i4 = i1 + UInt16(nLat)
                unitSphereIDataT.append(i1);  unitSphereIDataT.append(i2);  unitSphereIDataT.append(i3)
                unitSphereIDataT.append(i1);  unitSphereIDataT.append(i3);  unitSphereIDataT.append(i4)
            }
        }
        
        for s in 0 ..< nLat {
            var s2 = s+1; if s2 == nLat { s2 = 0 }
            unitSphereIDataT.append(UInt16(s))
            unitSphereIDataT.append(topIndex)
            unitSphereIDataT.append(UInt16(s2))
            
            unitSphereIDataT.append(UInt16(s + (nPitch-2)*nLat))
            unitSphereIDataT.append(UInt16(s2 + (nPitch-2)*nLat))
            unitSphereIDataT.append(topIndex+1)
        }
        
        let uSz = MemoryLayout<UInt16>.stride
        iBufferL = gDevice?.makeBuffer(bytes:unitSphereIDataL, length:unitSphereIDataL.count * uSz,  options:MTLResourceOptions())
        iBufferT = gDevice?.makeBuffer(bytes:unitSphereIDataT, length:unitSphereIDataT.count * uSz,  options:MTLResourceOptions())
    }
    
    //MARK: -

    func render(_ renderEncoder:MTLRenderCommandEncoder) {
        if unitSphereVData.count == 0 { return }

        renderEncoder.setVertexBuffer(vBuffer, offset: 0, index: 0)
        
        if vc.drawStyle == 1  {
            renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: unitSphereIDataT.count, indexType: MTLIndexType.uint16, indexBuffer: iBufferT!, indexBufferOffset:0)
        }
        else {
            renderEncoder.drawIndexedPrimitives(type: .line,  indexCount: unitSphereIDataL.count, indexType: MTLIndexType.uint16, indexBuffer: iBufferL!, indexBufferOffset:0)
        }
    }
}

extension TVertex {
    init(_ p:float3, _ ncolor:float4) {
        self.init()
        pos = p
        nrm = float3()
        txt = float2(0,0)
        color = ncolor
        drawStyle = 0
    }
}


