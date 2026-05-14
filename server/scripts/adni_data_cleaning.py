import pandas as pd
import numpy as np

# 1. Veriyi yükle (Dtype uyarısını engellemek için low_memory=False)
df = pd.read_csv("adni_master_table.csv", low_memory=False)

# 2. %90'dan fazla eksik verisi olan (senin listendeki ST41SV vb.) sütunları at
# TÜBİTAK raporundaki "Veri kalitesi kontrolü" adımı [cite: 282]
limit = len(df) * 0.1 
df_cleaned = df.dropna(thresh=limit, axis=1)

# 3. Sadece raporunda belirttiğin bağımsız değişkenleri ve kritik sütunları seç [cite: 232-236]
# Gereksiz sistem loglarını (USERDATE, UPDATE_STAMP vb.) temizleyelim
cols_to_keep = [c for c in df_cleaned.columns if not any(x in c for x in ['USERDATE', 'UPDATE_STAMP', 'ID_', 'LANGUAGE', 'LABEL'])]
df_final = df_cleaned[cols_to_keep]

# 4. Bağımlı Değişkeni (Label) Netleştir
# DIAGNOSIS sütunu boş olan satırları eğitimden çıkaralım
df_final = df_final.dropna(subset=['DIAGNOSIS'])

# 5. Baseline Filtresi (İsteğe Bağlı)
# 16 bin satır çok fazla tekrar içeriyor olabilir. 
# Eğer sadece ilk vizit üzerinden risk modellemek istersen:
# df_final = df_final[df_final['VISCODE'] == 'bl']

# 6. Temizlenmiş veriyi kaydet
df_final.to_csv("adni_master_cleaned.csv", index=False)

print(f"--- Temizlik Tamamlandı ---")
print(f"Orijinal sütun sayısı: 545")
print(f"Yeni sütun sayısı: {df_final.shape[1]}")
print(f"Kalan satır sayısı: {df_final.shape[0]}")