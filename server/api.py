from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import pandas as pd
import joblib
import os

# 1. FastAPI Uygulamasını Başlat
app = FastAPI(
    title="NeuroDetect API",
    description="ALS ve Alzheimer için Çok-Modaliteli Karar Destek Sistemi",
    version="1.0.0"
)

# 2. Modeli Yükle (Sunucu başlarken bir kez yüklenir)
model_path = "models/als_final_model.pkl"
if os.path.exists(model_path):
    model = joblib.load(model_path)
    print("NeuroDetect Yapay Zeka Modeli Başarıyla Yüklendi!")
else:
    model = None
    print("HATA: Model bulunamadı!")

# 3. Gelen Verinin Formatını Belirle (Pydantic Schema)
# Doctor Web Panel'den veya Patient App'ten gelecek veriler tam olarak bu formatta olmalı
class PatientData(BaseModel):
    age: int
    sex_encoded: int         # 0: Erkek, 1: Kadın
    alsfrs_delta: int        # Hastalığın başlangıcından geçen gün
    q1_speech: float         # Konuşma skoru (0-4)
    q2_salivation: float     # Salya skoru (0-4)
    q3_swallowing: float     # Yutma skoru (0-4)

# 4. Tahmin Noktası (Endpoint) Oluştur
@app.post("/predict")
def predict_als_score(data: PatientData):
    if model is None:
        raise HTTPException(status_code=500, detail="Yapay zeka modeli aktif değil.")
    
    # Gelen JSON verisini Pandas DataFrame'e çevir
    # Yapay zeka sadece bu tablo formatını anlar
    input_data = pd.DataFrame([data.model_dump()])
    
    # Modeli kullanarak tahmin yap
    prediction = model.predict(input_data)[0]
    
    # Doktorun paneline sonucu geri gönder
    return {
        "status": "success",
        "message": "Tahmin başarıyla hesaplandı.",
        "predicted_alsfrs_total": round(prediction, 1),
        "risk_level": "Yüksek Risk" if prediction < 24 else "Düşük Risk" # Basit bir risk kuralı
    }