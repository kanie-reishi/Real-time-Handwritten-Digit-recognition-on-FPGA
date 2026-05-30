import os
import json
import numpy as np
import sys

# Thêm thư mục model vào path để import hw_simulation
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "model")))
# pyrefly: ignore [missing-import]
import hw_simulation

OUT_DIR = "../tb/hex"

def export_hex(filename, data, is_32bit=False):
    os.makedirs(OUT_DIR, exist_ok=True)
    filepath = os.path.join(OUT_DIR, filename)
    with open(filepath, 'w') as f:
        if is_32bit:
            for val in data.flatten():
                hex_str = f"{np.uint32(val):08X}"
                f.write(hex_str + "\n")
        else:
            if len(data.shape) > 1 and data.shape[1] == 16:
                for row in data:
                    row_hex = "".join([f"{np.uint8(v):02X}" for v in reversed(row)])
                    f.write(row_hex + "\n")
            else:
                for val in data.flatten():
                    f.write(f"{np.uint8(val):02X}\n")
    print(f"Exported {filepath}")

def main():
    print("Loading weights from hw_simulation...")
    original_cwd = os.getcwd()
    
    # Xác định thư mục model một cách an toàn dựa trên vị trí file script này
    script_dir = os.path.dirname(os.path.abspath(__file__))
    model_dir = os.path.abspath(os.path.join(script_dir, "..", "model"))
    os.chdir(model_dir)
    
    weights, rs = hw_simulation.load_weights()
    
    # Chạy HW Simulator với một ảnh test (ảnh toàn số 1)
    img = np.full((1, 32, 32), 1, dtype=np.uint8)
    pred, mid = hw_simulation.hw_forward(img, weights, rs, verbose=False)
    
    os.chdir(original_cwd)
    
    # -------------------------------------------------------------------------
    # 1. IFM: Lấy từ đầu ra S4.
    # Kích thước: [16, 5, 5] -> Hardware: Cần [25, 16] (quét y, x, rồi đến 16 channel)
    # -------------------------------------------------------------------------
    s4_out = mid["s4_out"] # [16, 5, 5]
    ifm_hw = np.transpose(s4_out, (1, 2, 0)) # [5, 5, 16]
    ifm_hw = ifm_hw.reshape(25, 16)
    
    # -------------------------------------------------------------------------
    # 2. Weight: Lấy từ C5.
    # Kích thước: [120, 16, 5, 5]. Hardware chạy 8 pass (mỗi pass 16 kênh ra).
    # -------------------------------------------------------------------------
    c5_w = weights["c5_w"]
    weight_hw = np.zeros((8 * 25 * 16, 16), dtype=np.int8) 
    
    for p in range(8):
        c_start = p * 16
        c_end = min((p + 1) * 16, 120)
        c_len = c_end - c_start
        
        # Lấy 16 kênh ra cho pass này (Pad 0 nếu pass cuối chỉ có 8 kênh)
        w_chunk = np.zeros((16, 16, 5, 5), dtype=np.int8)
        w_chunk[0:c_len, :, :, :] = c5_w[c_start:c_end, :, :, :]
        
        # Hardware tự động Tiling theo kx, ky. FSM lặp ky trước, kx sau hay ngược lại?
        # Trong pea_top.sv: loop_kx tăng trước, loop_ky tăng sau.
        # Nghĩa là thứ tự tile sẽ là (0,0), (0,1), (0,2)... (4,4) (ky, kx).
        tile_idx = 0
        for ky in range(5):
            for kx in range(5):
                # Weight matrix cho Tile này: [16_out, 16_in]
                w_tile = w_chunk[:, :, ky, kx] 
                
                # Hardware cần Row = Cin, Col = Cout
                w_tile_hw = np.transpose(w_tile, (1, 0)) # [16_in, 16_out]
                
                row_start = p * 400 + tile_idx * 16
                weight_hw[row_start : row_start + 16, :] = w_tile_hw
                tile_idx += 1
                
    # -------------------------------------------------------------------------
    # 3. Bias: Lấy từ C5. Pad từ 120 lên 128.
    # -------------------------------------------------------------------------
    c5_b = weights["c5_b"]
    bias_hw = np.zeros(128, dtype=np.int32)
    bias_hw[0:120] = c5_b
    
    # -------------------------------------------------------------------------
    # 4. Expected OFM: Lấy đầu ra C5.
    # Kích thước: [120]. Pad lên 128, và format thành [8, 16] (8 pass).
    # -------------------------------------------------------------------------
    c5_out = mid["c5_out"] # [120]
    ofm_hw = np.zeros(128, dtype=np.int8)
    ofm_hw[0:120] = c5_out
    ofm_hw = ofm_hw.reshape(8, 16) 
    
    # Export Hex
    export_hex("ifm.hex", ifm_hw, is_32bit=False)
    export_hex("weight.hex", weight_hw, is_32bit=False)
    export_hex("bias.hex", bias_hw, is_32bit=True)
    export_hex("expected_ofm.hex", ofm_hw, is_32bit=False)
    
    print("\n[SUCCESS] Testbench data generated from Golden Model!")

if __name__ == "__main__":
    main()
