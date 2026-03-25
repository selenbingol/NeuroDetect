import torch
import torch.nn as nn
import torch.nn.functional as F

class NeuroDetectModel(nn.Module):
    def __init__(self, mri_dim=3, clinical_dim=6, game_dim=3, num_classes=3):
        super(NeuroDetectModel, self).__init__()
        
        # 1. MRI Özellik Çıkarıcı (MRI Encoder)
        self.mri_branch = nn.Sequential(
            nn.Linear(mri_dim, 16),
            nn.ReLU(),
            nn.Dropout(0.2)
        )
        
        # 2. Klinik Özellik Çıkarıcı (Clinical Encoder)
        self.clinical_branch = nn.Sequential(
            nn.Linear(clinical_dim, 16),
            nn.ReLU(),
            nn.Dropout(0.2)
        )
        
        # 3. Oyun/Dijital Biyobelirteç Özellik Çıkarıcı (Game Encoder)
        self.game_branch = nn.Sequential(
            nn.Linear(game_dim, 16),
            nn.ReLU(),
            nn.Dropout(0.2)
        )
        
        # 4. ÇOK-MODALİTELİ TEMSİL ALANI (Fusion Layer)
        # Üç koldan gelen 16'şar birimlik veriyi birleştiriyoruz (16+16+16 = 48)
        self.fusion_layer = nn.Sequential(
            nn.Linear(16 + 16 + 16, 32),
            nn.ReLU(),
            nn.Linear(32, num_classes) # Sonuç: AH, ALS veya Sağlıklı
        )

    def forward(self, mri_data, clinical_data, game_data):
        # Her veriyi kendi kolunda işle
        mri_feat = self.mri_branch(mri_data)
        clin_feat = self.clinical_branch(clinical_data)
        game_feat = self.game_branch(game_data)
        
        # VERİ FÜZYONU: Üç farklı dünyadan gelen bilgiyi tek bir vektörde birleştir
        combined = torch.cat((mri_feat, clin_feat, game_feat), dim=1)
        
        # Final Sınıflandırma
        logits = self.fusion_layer(combined)
        return logits

# Model Testi (Sadece mimariyi kontrol etmek için)
if __name__ == "__main__":
    # Örnek (dummy) veriler oluşturuyoruz
    sample_mri = torch.randn(1, 3)
    sample_clin = torch.randn(1, 6)
    sample_game = torch.randn(1, 3)
    
    model = NeuroDetectModel()
    output = model(sample_mri, sample_clin, sample_game)
    
    print("--- MODEL MİMARİSİ OLUŞTURULDU ---")
    print(f"Model Çıktısı (Logits): {output}")
    print(f"Tahmin Edilen Sınıf: {torch.argmax(output, dim=1).item()}")