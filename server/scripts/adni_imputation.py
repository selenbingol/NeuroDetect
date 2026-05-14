import pandas as pd
import numpy as np
from sklearn.experimental import enable_iterative_imputer  
from sklearn.impute import IterativeImputer
from sklearn.preprocessing import LabelEncoder

def prepare_ml_data():
    print("1. Veri Yükleniyor...")
    df = pd.read_csv("adni_master_cleaned.csv", low_memory=False)

    # 1. HEDEF DEĞİŞKEN (LABEL) KONTROLÜ
    orijinal_satir = len(df)
    df = df.dropna(subset=['DIAGNOSIS'])
    print(f"Tanısı olmayan {orijinal_satir - len(df)} satır çıkarıldı. Kalan: {len(df)}")

    # 2. KİMLİK VE HEDEF SÜTUNLARINI AYIRMA
    identifiers = df[['RID', 'VISCODE', 'DIAGNOSIS']].copy()
    features = df.drop(columns=['RID', 'VISCODE', 'DIAGNOSIS', 'PTID', 'PHASE'], errors='ignore')

    # 3. KATEGORİK VERİLERİ (METİNLERİ) SAYISALLAŞTIRMA (HATA DÜZELTİLDİ)
    print("2. Metinsel veriler sayısallaştırılıyor (Encoding)...")
    for col in features.select_dtypes(include=['object', 'string']).columns:
        le = LabelEncoder()
        mask = features[col].notnull()
        
        # Sütunu önce 'object' tipine çeviriyoruz ki Pandas sayı yazmamıza itiraz etmesin
        features[col] = features[col].astype('object') 
        
        # Sadece boş olmayan satırları encode et
        features.loc[mask, col] = le.fit_transform(features.loc[mask, col].astype(str))
        
        # Tüm sütunu sayısal tipe (float) çevir (çünkü içinde NaN boşluklar var)
        features[col] = pd.to_numeric(features[col], errors='coerce')

    # 4. ÇOKLU ATAMA (MULTIPLE IMPUTATION - MICE)
    print("3. Çoklu Atama (MICE) algoritması çalışıyor... (Lütfen bekleyin, birkaç dakika sürebilir)")
    # max_iter=10 ve tol ayarları ile algoritmayı hızlandırıyoruz
    imputer = IterativeImputer(max_iter=10, random_state=42, verbose=2) 
    features_imputed = imputer.fit_transform(features)

    # 5. TABLOYU YENİDEN BİRLEŞTİRME VE KAYDETME
    print("4. Temiz veri seti oluşturuluyor...")
    features_imputed_df = pd.DataFrame(features_imputed, columns=features.columns, index=features.index)
    
    # Kimlikler ve doldurulmuş özellikleri yan yana birleştir
    df_final = pd.concat([identifiers, features_imputed_df], axis=1)

    output_name = "adni_ml_ready.csv"
    df_final.to_csv(output_name, index=False)
    
    print(f"\n--- MÜKEMMEL SONUÇ ---")
    print(f"Sıfır eksik verili, makine öğrenmesine hazır tablo: '{output_name}'")
    print(f"Nihai Boyut: {df_final.shape}")

if __name__ == "__main__":
    prepare_ml_data()