from flask import Flask, request, jsonify
from flask_cors import CORS
import torch
from pathlib import Path
from model import NeuroDetectModel
import torch.nn.functional as F

app = Flask(__name__)
CORS(app) # Diğer uygulamaların (Flutter/Web) erişimine izin verir

# 1. YOLLAR VE ETİKETLER
BASE_DIR = Path(__file__).resolve().parent
MODEL_PATH = BASE_DIR / "neurodetect_model.pth"
CLASSES = ["Riskli (Converted)", "Alzheimer (Demented)", "Sağlıklı (Nondemented)"]

# 2. MODELİ YÜKLE
model = NeuroDetectModel()
if MODEL_PATH.exists():
    model.load_state_dict(torch.load(MODEL_PATH, weights_only=True))
    model.eval()
    print("✅ Yapay Zeka Modeli Başarıyla Yüklendi!")
else:
    print("❌ HATA: Model dosyası bulunamadı!")

# 3. NORMALİZASYON FONKSİYONU (Predict.py ile aynı mantık)
def normalize_data(mri, clinical, game):
    mri_n = [(mri[0]-1500)/200, (mri[1]-0.7)/0.05, (mri[2]-1.0)/0.1]
    clin_n = [
        (clinical[0]-77)/7, (clinical[1]-14)/3, (clinical[2]-2)/1,
        (clinical[3]-27)/3, (clinical[4]-0.3)/0.4, (clinical[5]-0.5)/0.5
    ]
    game_n = [(game[0]-650)/150, (game[1]-0.8)/0.1, (game[2]-5)/3]
    return mri_n, clin_n, game_n

# 4. TAHMİN ENDPOINT'İ (Servis Kapısı)
@app.route('/predict', methods=['POST'])
def predict():
    try:
        data = request.get_json()
        
        # Gelen verileri al
        mri_vals = data['mri']
        clin_vals = data['clinical']
        game_vals = data['game']

        # Verileri hazırla
        mri_n, clin_n, game_n = normalize_data(mri_vals, clin_vals, game_vals)
        
        mri_t = torch.tensor([mri_n], dtype=torch.float32)
        clin_t = torch.tensor([clin_n], dtype=torch.float32)
        game_t = torch.tensor([game_n], dtype=torch.float32)

        # Tahmin yap
        with torch.no_grad():
            logits = model(mri_t, clin_t, game_t)
            probs = F.softmax(logits, dim=1)
            pred_idx = torch.argmax(probs, dim=1).item()

        # Sonucu JSON olarak döndür
        return jsonify({
            "status": "success",
            "prediction": CLASSES[pred_idx],
            "confidence": f"{probs[0][pred_idx]*100:.2f}%",
            "all_probabilities": {CLASSES[i]: f"{probs[0][i]*100:.2f}%" for i in range(len(CLASSES))}
        })

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 400

if __name__ == '__main__':
    # 0.0.0.0 sayesinde ağdaki diğer cihazlar (telefonun gibi) erişebilir
    app.run(host='0.0.0.0', port=5000, debug=True)