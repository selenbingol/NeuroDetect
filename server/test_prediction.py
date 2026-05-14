import pandas as pd
import joblib

# 1. Eğittiğimiz modeli yükleyelim
model_path = "server/als_prediction_model.pkl"

try:
    model = joblib.load(model_path)
    print("Model başarıyla yüklendi: " + model_path)
except FileNotFoundError:
    print(f"HATA: Model bulunamadı. Önce model_training.py dosyasını çalıştırdığından emin ol.")
    exit()

print("-" * 40)
print("NeuroDetect: Karar Destek Sistemi Testi")
print("-" * 40)

# 2. Hayali Hastalarımızı Oluşturalım
# Özellik Sırası: ['age', 'sex_encoded', 'alsfrs_delta', 'q1_speech', 'q2_salivation', 'q3_swallowing']
# Cinsiyet: 0=Erkek, 1=Kadın

# HASTA 1: Yeni Teşhis (Hafif Semptomlar)
# 55 Yaş, Erkek, 30. Gün. Konuşma: Normal(4), Salya: Normal(4), Yutma: Normal(4)
hasta_yeni = pd.DataFrame([[55, 0, 30, 4, 4, 4]], 
                          columns=['age', 'sex_encoded', 'alsfrs_delta', 'q1_speech', 'q2_salivation', 'q3_swallowing'])

# HASTA 2: İleri Evre (Belirgin Semptomlar)
# 65 Yaş, Kadın, 400. Gün. Konuşma: Anlaşılmaz(1), Salya: Çok(2), Yutma: Sıvı Tüketebiliyor(2)
hasta_ileri = pd.DataFrame([[65, 1, 400, 1, 2, 2]], 
                           columns=['age', 'sex_encoded', 'alsfrs_delta', 'q1_speech', 'q2_salivation', 'q3_swallowing'])

# 3. Modelimiz Tahmin Yürütüyor
tahmin_yeni = model.predict(hasta_yeni)[0]
tahmin_ileri = model.predict(hasta_ileri)[0]

# 4. Sonuçları Doktorun Önüne Sunalım (ALSFRS Maksimum Skor: 48)
print(f"\n HASTA 1 (Yeni Teşhis - 55 Yaş, Erkek, 1. Ay)")
print(f"   Klinik Gözlem: Konuşma ve yutma normal.")
print(f"   Yapay Zeka Tahmini (ALSFRS Toplam Skoru): {tahmin_yeni:.1f} / 48.0")
print(f"   Sistem Yorumu: Hastalık başlangıç evresinde, motor fonksiyonlar büyük ölçüde korunuyor.")

print(f"\n HASTA 2 (İleri Evre - 65 Yaş, Kadın, 13. Ay)")
print(f"   Klinik Gözlem: Konuşma güçlüğü ve yutma zorluğu mevcut.")
print(f"   Yapay Zeka Tahmini (ALSFRS Toplam Skoru): {tahmin_ileri:.1f} / 48.0")
print(f"   Sistem Yorumu: Hastalık ilerlemiş durumda, yakın takip ve destekleyici tedavi (örn: beslenme tüpü) değerlendirilmeli.")

print("\n" + "-" * 40)