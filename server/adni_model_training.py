import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, accuracy_score
import joblib

def train_baseline_model():
    print("1. Temizlenmiş ve çoklu atama yapılmış veri yükleniyor...")
    df = pd.read_csv("adni_ml_ready.csv", low_memory=False)

    # ---------------------------------------------------------
    # 🛠️ 1. ADIM: KOPYA ÇEKMEYİ (DATA LEAKAGE) ÖNLEME
    # ---------------------------------------------------------
    y = df['DIAGNOSIS']
    
    # Modelin ezber yapmasını sağlayan "hileli" ve gereksiz sütunlar çıkarılıyor
    leakage_cols = [
        'RID', 'VISCODE', 'DIAGNOSIS', 'PTID', 'PHASE', 
        'PTADDX', 'MMDATE', 'MMYEAR', 'MMMONTH', 'MMDAY', 
        'MMFLOOR', 'SITEID', 'ID', 'USERDATE', 'UPDATE_STAMP'
    ]
    X = df.drop(columns=leakage_cols, errors='ignore')

    # ---------------------------------------------------------
    # 🛠️ 2. ADIM: SAYISAL PATLAMALARI (INFINITY) ENGELLEME
    # ---------------------------------------------------------
    print("-> Veri sınırları dengeleniyor (Clipping)...")
    max_float32 = np.finfo(np.float32).max / 10 
    X = np.clip(X, a_min=-max_float32, a_max=max_float32)
    X = X.replace([np.inf, -np.inf], np.nan).fillna(0)

    # ---------------------------------------------------------
    # 🤖 3. ADIM: EĞİTİM VE TEST SETLERİNE AYIRMA
    # ---------------------------------------------------------
    print("2. Veri eğitim ve test setlerine ayrılıyor...")
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42, stratify=y)

    # ---------------------------------------------------------
    # 🌲 4. ADIM: MODELİN KURULMASI VE EĞİTİLMESİ
    # ---------------------------------------------------------
    print("3. Random Forest modeli eğitiliyor... (Bu işlem birkaç saniye sürebilir)")
    model = RandomForestClassifier(n_estimators=100, random_state=42, class_weight='balanced', n_jobs=-1)
    model.fit(X_train, y_train)

    # ---------------------------------------------------------
    # 📊 5. ADIM: BAŞARI RAPORU
    # ---------------------------------------------------------
    print("\n4. Model Başarı Raporu (Classification Report):")
    y_pred = model.predict(X_test)
    print("-" * 50)
    print(classification_report(y_test, y_pred))
    print("-" * 50)
    print(f"Genel Doğruluk (Accuracy): % {accuracy_score(y_test, y_pred) * 100:.2f}")

    # ---------------------------------------------------------
    # 🔍 6. ADIM: AÇIKLANABİLİRLİK (XAI) - ÖZELLİK ÖNEMİ
    # ---------------------------------------------------------
    print("\n5. Model için En Önemli 15 Özellik (Biyobelirteçler):")
    feature_importances = pd.DataFrame({
        'Özellik': X.columns,
        'Önem Skoru': model.feature_importances_
    }).sort_values(by='Önem Skoru', ascending=False)
    
    print(feature_importances.head(15))

    # Modeli Kaydetme
    model_filename = "alzheimer_baseline_model.pkl"
    joblib.dump(model, model_filename)
    print(f"\nModel başarıyla '{model_filename}' olarak kaydedildi!")

if __name__ == "__main__":
    train_baseline_model()