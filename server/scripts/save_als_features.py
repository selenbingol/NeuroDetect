"""
NeuroDetect — ALS Model Feature İsimlerini Kurtarma Scripti

PRO-ACT modeli (als_final_model.pkl) eğitilirken feature isimleri
SimpleImputer nedeniyle kayboldu. Bu script:
  1. Orijinal proact_master_table.csv'yi yükler
  2. Aynı preprocessing adımlarını uygular
  3. Feature listesini models/als_feature_names.json'a kaydeder
  4. ALS modelini FEATURE İSİMLERİYLE birlikte yeniden kaydeder

Ardından clinical_proxy.py güncellenebilir.

Çalıştırmak için:
  cd server
  python scripts/save_als_features.py
"""

import os
import sys
import json
import numpy as np
import pandas as pd
import joblib
from sklearn.impute import SimpleImputer

# server/scripts/save_als_features.py
#   -> dirname  = server/scripts/
#   -> dirname  = server/
#   -> dirname  = NeuroDetect/  (proje koku)
BASE_DIR   = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA_PATH  = os.path.join(BASE_DIR, "data", "processed", "proact_master_table.csv")
MODEL_DIR  = os.path.join(BASE_DIR, "server", "models")
MODEL_PATH = os.path.join(MODEL_DIR, "als_final_model.pkl")
OUTPUT_JSON = os.path.join(MODEL_DIR, "als_feature_names.json")


def main():
    # ── Kontroller ──
    if not os.path.exists(DATA_PATH):
        print(f"❌ Veri bulunamadı: {DATA_PATH}")
        print("   Önce proact_master_merge.py çalıştırın.")
        sys.exit(1)

    if not os.path.exists(MODEL_PATH):
        print(f"❌ Model bulunamadı: {MODEL_PATH}")
        sys.exit(1)

    # ── Veriyi Yükle & Aynı Preprocessing ──
    print("1. PRO-ACT verisi yükleniyor...")
    df = pd.read_csv(DATA_PATH, low_memory=False)
    print(f"   Boyut: {df.shape}")

    hedef = "ALSFRS_R_Total" if "ALSFRS_R_Total" in df.columns else "ALSFRS_Total"
    if hedef not in df.columns:
        print(f"❌ Hedef sütun bulunamadı ({hedef}). Mevcut sütunlar:")
        print(df.columns.tolist()[:20])
        sys.exit(1)

    df = df.dropna(subset=[hedef])

    leakage_cols = [
        hedef, "RISK_LABEL", "subject_id", "ALSFRS_Total", "ALSFRS_Delta",
        "Q1_Speech", "Q2_Salivation", "Q3_Swallowing", "Q4_Handwriting",
        "Q5a_Cutting_without_Gastrostomy", "Q5b_Cutting_with_Gastrostomy",
        "Q6_Dressing_and_Hygiene", "Q7_Turning_in_Bed", "Q8_Walking",
        "Q10_Respiratory", "R_1_Dyspnea", "R_2_Orthopnea",
        "R_3_Respiratory_Insufficiency",
    ]
    X = df.drop(columns=leakage_cols, errors="ignore")
    X = X.select_dtypes(include=[np.number])
    X = X.dropna(axis=1, how="all")

    feature_names = X.columns.tolist()
    print(f"2. Feature sayısı: {len(feature_names)}")
    print(f"   İlk 10: {feature_names[:10]}")

    # ── Model ile Feature Sayısı Eşleşiyor mu? ──
    model = joblib.load(MODEL_PATH)
    expected = model.n_features_in_
    if len(feature_names) != expected:
        print(f"⚠️  Uyumsuzluk! Model {expected} feature bekliyor, bizde {len(feature_names)} var.")
        print("   Bu olabilir çünkü aynı preprocessing tamamen aynı değil.")
        print("   Yine de feature listesini kaydediyoruz...")
    else:
        print(f"✅ Feature sayısı eşleşiyor: {expected}")

    # ── JSON'a Kaydet ──
    with open(OUTPUT_JSON, "w") as f:
        json.dump(feature_names, f, indent=2)
    print(f"✅ Feature isimleri kaydedildi: {OUTPUT_JSON}")

    # ── Modeli feature_names_in_ ile Güncelle ──
    # scikit-learn'ün feature_names_in_ attribute'unu ayarla
    if len(feature_names) == expected:
        model.feature_names_in_ = np.array(feature_names)
        joblib.dump(model, MODEL_PATH)
        print(f"✅ Model feature isimleriyle güncellendi: {MODEL_PATH}")
        print("\nArtık clinical_proxy.py'deki _build_als_feature_vector() aktif edilebilir!")
    else:
        print("\n⚠️  Model güncellenmedi — feature sayısı uyuşmuyor.")
        print("   Manuel inceleme gerekiyor.")
        # Sadece JSON'ı kaydetmekle yetindik


if __name__ == "__main__":
    main()
