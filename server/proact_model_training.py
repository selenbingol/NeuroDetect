import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, accuracy_score
from sklearn.impute import SimpleImputer
import joblib
import os

def train_proact_model():
    BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    DATA_PATH = os.path.join(BASE_DIR, "data", "processed", "proact_master_table.csv")
    
    if not os.path.exists(DATA_PATH):
        print(f"❌ HATA: {DATA_PATH} bulunamadı!")
        return

    print("1. Çok-Modaliteli ALS verisi yükleniyor...")
    df = pd.read_csv(DATA_PATH, low_memory=False)

    # 🎯 2. ADIM: HEDEF BELİRLEME
    hedef = 'ALSFRS_R_Total' if 'ALSFRS_R_Total' in df.columns else 'ALSFRS_Total'
    df = df.dropna(subset=[hedef])
    medyan_skor = df[hedef].median()
    df['RISK_LABEL'] = np.where(df[hedef] < medyan_skor, 1, 0)
    y = df['RISK_LABEL']

    # 🚨 3. ADIM: KOPYA ÇEKMEYİ ÖNLEME
    leakage_cols = [
        hedef, 'RISK_LABEL', 'subject_id', 'ALSFRS_Total', 'ALSFRS_Delta',
        'Q1_Speech', 'Q2_Salivation', 'Q3_Swallowing', 'Q4_Handwriting', 
        'Q5a_Cutting_without_Gastrostomy', 'Q5b_Cutting_with_Gastrostomy', 
        'Q6_Dressing_and_Hygiene', 'Q7_Turning_in_Bed', 'Q8_Walking', 
        'Q10_Respiratory', 'R_1_Dyspnea', 'R_2_Orthopnea', 'R_3_Respiratory_Insufficiency'
    ]
    X = df.drop(columns=leakage_cols, errors='ignore')
    X = X.select_dtypes(include=[np.number])

    # 🛠️ 4. ADIM: VERİ TEMİZLİĞİ (GÜNCELLENDİ ✅)
    print("-> Tamamen boş sütunlar ayıklanıyor...")
    # İçinde hiç veri olmayan (tamamı NaN) sütunları manuel atıyoruz
    X = X.dropna(axis=1, how='all')
    
    print("-> Eksik veriler medyan ile dolduruluyor...")
    imputer = SimpleImputer(strategy='median')
    X_imputed = imputer.fit_transform(X)
    
    # Artık X.columns ile X_imputed tam uyumlu!
    kept_columns = X.columns

    # 🤖 5. ADIM: EĞİTİM
    print("2. Veri setleri ayrılıyor ve model eğitiliyor...")
    X_train, X_test, y_train, y_test = train_test_split(X_imputed, y, test_size=0.2, random_state=42, stratify=y)
    
    model = RandomForestClassifier(n_estimators=100, random_state=42, class_weight='balanced', n_jobs=-1)
    model.fit(X_train, y_train)

    # 📊 6. ADIM: SONUÇLAR
    y_pred = model.predict(X_test)
    print("\n" + "="*40)
    print("   ALS MODEL BAŞARI RAPORU (FINAL)")
    print("="*40)
    print(classification_report(y_test, y_pred))
    print(f"Genel Doğruluk (Accuracy): % {accuracy_score(y_test, y_pred) * 100:.2f}")

    print("\n--- 🧠 En Önemli 10 Biyobelirteç ---")
    feature_importances = pd.DataFrame({
        'Özellik': kept_columns,
        'Önem': model.feature_importances_
    }).sort_values(by='Önem', ascending=False)
    print(feature_importances.head(10))

    joblib.dump(model, "als_final_model.pkl")
    print("\n✅ ALS Modeli başarıyla kaydedildi!")

if __name__ == "__main__":
    train_proact_model()