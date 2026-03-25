import pandas as pd
import numpy as np
import torch
from torch.utils.data import Dataset, DataLoader
from sklearn.preprocessing import StandardScaler, LabelEncoder
from pathlib import Path

# 1. DOSYA YOLLARI (En üstte kalabilir)
BASE_DIR = Path(__file__).resolve().parent
CSV_PATH = BASE_DIR / "data" / "dementia_dataset.csv"

# 2. SINIF TANIMI (Önce Python'a bunun ne olduğunu öğretiyoruz)
class NeuroDetectDataset(Dataset):
    def __init__(self, csv_file):
        # Veriyi Yükle
        self.data = pd.read_csv(csv_file)
        
        # Eksik Verileri Temizleme
        self.data['SES'] = self.data['SES'].fillna(self.data['SES'].median())
        self.data['MMSE'] = self.data['MMSE'].fillna(self.data['MMSE'].median())
        
        # Kategorik Verileri Sayısallaştırma
        le = LabelEncoder()
        self.data['M/F'] = le.fit_transform(self.data['M/F'])
        self.data['Hand'] = le.fit_transform(self.data['Hand'])
        self.data['Group'] = le.fit_transform(self.data['Group'])
        self.labels = self.data['Group'].values
        
        # Nörogörüntüleme Özellikleri (MRI)
        mri_features = self.data[['eTIV', 'nWBV', 'ASF']].values
        
        # Klinik Özellikler
        clinical_features = self.data[['Age', 'EDUC', 'SES', 'MMSE', 'CDR', 'M/F']].values
        
        # Sentetik Oyun Verisi Üretimi (Digital Biomarkers)
        game_features = []
        for label in self.labels:
            if label == 0: # Sağlıklı
                game_features.append([np.random.normal(500, 50), np.random.normal(0.90, 0.05), np.random.poisson(2)])
            else: # Hasta
                game_features.append([np.random.normal(850, 100), np.random.normal(0.65, 0.10), np.random.poisson(8)])
            
        game_features = np.array(game_features)
        
        # Normalizasyon
        scaler = StandardScaler()
        self.mri_features = scaler.fit_transform(mri_features)
        self.clinical_features = scaler.fit_transform(clinical_features)
        self.game_features = scaler.fit_transform(game_features)

    def __len__(self):
        return len(self.data)

    def __getitem__(self, idx):
        mri = torch.tensor(self.mri_features[idx], dtype=torch.float32)
        clinical = torch.tensor(self.clinical_features[idx], dtype=torch.float32)
        game = torch.tensor(self.game_features[idx], dtype=torch.float32)
        label = torch.tensor(self.labels[idx], dtype=torch.long)
        return {'mri': mri, 'clinical': clinical, 'game': game}, label

# 3. TEST BLOĞU (Sadece bu dosya doğrudan çalıştırılırsa çalışır)
if __name__ == "__main__":
    # Burada CSV_PATH'i kullanıyoruz
    if CSV_PATH.exists():
        dataset = NeuroDetectDataset(CSV_PATH)
        dataloader = DataLoader(dataset, batch_size=16, shuffle=True)
        features, labels = next(iter(dataloader))
        
        print("--- ÇOK-MODALİTELİ VERİ YÜKLEYİCİ TESTİ BAŞARILI ---")
        print(f"Toplam Veri: {len(dataset)}")
        print(f"MRI Boyutu: {features['mri'].shape}")
    else:
        print(f"HATA: {CSV_PATH} konumunda dosya bulunamadı!")