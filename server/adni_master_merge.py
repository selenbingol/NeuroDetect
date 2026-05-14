import pandas as pd
import os

# 1. DOSYA YOLLARINI AYARLA
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, "data", "raw", "adni") 

print(f"--- NeuroDetect Veri Operasyonu ---")
print(f"Veri yolu: {DATA_DIR}")

# 2. KRİTİK DOSYALAR
ADNI_FILES = {
    'target': 'DXSUM_05May2026.csv',
    'mmse': 'MMSE_05May2026.csv',
    'adas': 'adas.csv',
    'genomic': 'APOERES_05May2026.csv',
    'demog': 'ptdemog.csv',
    'mri': 'ucsffsl.csv'
}

def merge_adni_data():
    target_path = os.path.join(DATA_DIR, ADNI_FILES['target'])
    if not os.path.exists(target_path):
        print(f"HATA: {target_path} bulunamadı!")
        return

    # 1. ADIM: DXSUM dosyasını yükle ve sütunları temizle
    master = pd.read_csv(target_path)
    
    # Sütun isimlerini büyük harfe çevirerek kontrol edelim (Büyük/Küçük harf hatasını önler)
    master.columns = [c.upper() for c in master.columns]
    
    # Mevcut olan en iyi hedef sütununu seç (DXCHANGE veya DIAGNOSIS) [cite: 230, 235]
    available_columns = master.columns.tolist()
    keys_to_keep = ['RID', 'VISCODE']
    
    if 'DXCHANGE' in available_columns:
        keys_to_keep.append('DXCHANGE')
    elif 'DIAGNOSIS' in available_columns:
        keys_to_keep.append('DIAGNOSIS')
    else:
        # Eğer ikisi de yoksa, mevcut sütunları göster ve ilk 3'ü al
        print(f"UYARI: 'DXCHANGE' bulunamadı. Mevcut sütunlar: {available_columns[:10]}...")
        # En azından RID ve VISCODE'u kurtaralım
        keys_to_keep = [c for c in ['RID', 'VISCODE'] if c in available_columns]

    master = master[keys_to_keep]

    # 2. ADIM: Diğer modaliteleri birleştir
    for key, filename in ADNI_FILES.items():
        if key == 'target': continue
        
        file_path = os.path.join(DATA_DIR, filename)
        if os.path.exists(file_path):
            print(f"Birleştiriliyor: {filename}")
            df_temp = pd.read_csv(file_path)
            df_temp.columns = [c.upper() for c in df_temp.columns] # Sütunları standartlaştır
            
            if 'VISCODE' in df_temp.columns:
                master = pd.merge(master, df_temp, on=['RID', 'VISCODE'], how='left', suffixes=('', f'_{key}'))
            else:
                master = pd.merge(master, df_temp, on='RID', how='left', suffixes=('', f'_{key}'))
        else:
            print(f"UYARI: {filename} bulunamadı, atlanıyor.")

    # 3. ADIM: Kaydet
    output_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "adni_master_table.csv")
    master.to_csv(output_path, index=False)
    print(f"\nİŞLEM BAŞARILI! Master tablo hazır: {output_path}")

if __name__ == "__main__":
    merge_adni_data()
