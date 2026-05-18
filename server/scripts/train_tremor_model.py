import os
import glob
import pandas as pd
import numpy as np
import joblib
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix

def extract_features(df, window_size=50):
    """
    Ham zaman serisi verisini pencerelere (windows) böler ve 
    her pencere için istatistiksel özellikler (mean, std vb.) çıkarır.
    """
    features = []
    labels = []
    
    # Tüm veriyi baştan sona window_size büyüklüğünde adımlarla geziyoruz
    for i in range(0, len(df) - window_size, window_size // 2): # %50 overlapping (örtüşme)
        window = df.iloc[i:i + window_size]
        
        # Etiket: Bu penceredeki en yaygın etiket (mode)
        label = window['label'].mode()[0]
        
        feature_dict = {}
        
        # Flutter'ın backend'e yolladığı 3 temel özelliği birebir simüle ediyoruz:
        # 1. avg_motion (motion sütununun ortalaması)
        feature_dict['avg_motion'] = window['motion'].mean()
        
        # 2. avg_gyro (gyro sütununun ortalaması)
        feature_dict['avg_gyro'] = window['gyro'].mean()
        
        # 3. movement_variability (gyro sütununun standart sapması)
        # Flutter tarafında sqrt(variance) kullanılıyor, bu tam olarak standart sapmadır.
        feature_dict['movement_variability'] = window['gyro'].std()
        
        # NaN kontrolü (standart sapma tek elemanlı pencerede NaN verebilir)
        feature_dict['movement_variability'] = feature_dict['movement_variability'] if not pd.isna(feature_dict['movement_variability']) else 0.0

        features.append(feature_dict)
        labels.append(label)
        
    return pd.DataFrame(features), np.array(labels)

def train_model():
    print("="*50)
    print("TREMOR / HAREKET YAPAY ZEKA MODELİ EĞİTİMİ".center(50))
    print("="*50)
    
    # 1. Verileri Oku
    data_dir = os.path.join(os.path.dirname(__file__), "..", "data", "sensor_dataset")
    csv_files = glob.glob(os.path.join(data_dir, "*.csv"))
    
    if not csv_files:
        print(f"HATA: {data_dir} klasöründe hiç CSV dosyası bulunamadı!")
        print("Lütfen önce collect_sensor_data.py ile veri toplayın.")
        return
        
    print(f"Toplam {len(csv_files)} adet veri dosyası bulundu. İşleniyor...")
    
    all_features = []
    all_labels = []
    
    for file in csv_files:
        try:
            df = pd.read_csv(file)
            if df.empty or len(df) < 50:
                continue
                
            # Özellik çıkarımı (Feature Extraction)
            X_windowed, y_windowed = extract_features(df, window_size=50) # 50 satırlık pencereler
            all_features.append(X_windowed)
            all_labels.extend(y_windowed)
        except Exception as e:
            print(f"Dosya okuma hatası ({file}): {e}")
            
    if not all_features:
        print("HATA: Yeterli geçerli veri bulunamadı.")
        return
        
    # Tüm verileri birleştir
    X = pd.concat(all_features, ignore_index=True)
    y = np.array(all_labels)
    
    print(f"\nÖzellik çıkarımı tamamlandı. Toplam örnek (pencere) sayısı: {len(X)}")
    print(f"Özellik sayısı: {X.shape[1]}")
    
    # Sınıf dağılımını kontrol et
    unique, counts = np.unique(y, return_counts=True)
    dist = dict(zip(unique, counts))
    print(f"Sınıf Dağılımı: 0 (Normal): {dist.get(0, 0)}, 1 (Tremor): {dist.get(1, 0)}")
    
    if len(unique) < 2:
        print("\nUYARI: Modeli eğitebilmek için hem '0' hem de '1' etiketli veriye ihtiyacınız var!")
        print("Lütfen eksik olan sınıf için veri toplayın.")
        return

    # 2. Veriyi Eğitim ve Test Olarak Böl
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42, stratify=y)
    
    # 3. Modeli Eğit (Random Forest - Sağlık verilerinde çok başarılıdır)
    print("\nModel eğitiliyor (Random Forest)...")
    clf = RandomForestClassifier(n_estimators=100, max_depth=10, random_state=42)
    clf.fit(X_train, y_train)
    
    # 4. Modeli Test Et
    y_pred = clf.predict(X_test)
    acc = accuracy_score(y_test, y_pred)
    
    print("\n" + "-"*30)
    print(f"MODEL BAŞARISI (ACCURACY): %{acc * 100:.2f}")
    print("-"*30)
    print("\nDetaylı Rapor:")
    print(classification_report(y_test, y_pred, target_names=["Normal (0)", "Tremor (1)"]))
    
    # 5. Modeli Kaydet
    models_dir = os.path.join(os.path.dirname(__file__), "..", "models")
    os.makedirs(models_dir, exist_ok=True)
    
    model_path = os.path.join(models_dir, "tremor_ml_model.pkl")
    
    # Feature isimlerini de kaydedelim (daha sonra tahmin yaparken lazım olacak)
    model_data = {
        'model': clf,
        'feature_names': list(X.columns)
    }
    
    joblib.dump(model_data, model_path)
    print(f"\n✅ Model başarıyla kaydedildi: {model_path}")
    print("Artık bu modeli server tarafında clinical_proxy.py içerisinde kullanabilirsiniz!")

if __name__ == "__main__":
    train_model()
