import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os

# Temizlenmiş veriyi oku
df = pd.read_csv("data/processed/proact_cleaned.csv")

# Görselleştirme için stil ayarla
sns.set_theme(style="whitegrid")

# İki grafik yan yana olsun
fig, axes = plt.subplots(1, 2, figsize=(15, 6))

# 1. Yaş Dağılımı
sns.histplot(df['age'], bins=20, kde=True, ax=axes[0], color='skyblue')
axes[0].set_title('Hasta Yaş Dağılımı')
axes[0].set_xlabel('Yaş')
axes[0].set_ylabel('Hasta Sayısı')

# 2. ALSFRS Toplam Skor Dağılımı (Hastalık Şiddeti)
sns.histplot(df['alsfrs_total'], bins=15, kde=True, ax=axes[1], color='salmon')
axes[1].set_title('ALSFRS Toplam Skor Dağılımı')
axes[1].set_xlabel('ALSFRS Skoru (Düşük = Şiddetli)')
axes[1].set_ylabel('Kayıt Sayısı')

plt.tight_layout()
plt.show()

# Temel istatistikleri ekrana yazdır
print("\n--- Veri Seti İstatistikleri ---")
print(df[['age', 'alsfrs_total']].describe())