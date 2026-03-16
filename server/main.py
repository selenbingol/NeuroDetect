from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import psycopg2
from pydantic import BaseModel

app = FastAPI()

# CORS Ayarları
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_URL = "postgresql://neondb_owner:npg_y1YGSLtIZW0B@ep-rough-star-agysl1zm-pooler.c-2.eu-central-1.aws.neon.tech/neondb?sslmode=require"

class GameMetricsData(BaseModel):
    session_id: int
    score: int
    reaction_time_ms: int
    accuracy_rate: float

# 1. OTURUM BAŞLATMA KAPISI (Bu çalışıyor)
@app.post("/start-session")
async def start_session():
    conn = None
    try:
        conn = psycopg2.connect(DB_URL)
        cur = conn.cursor()
        
        # Test kullanıcısını kontrol et
        cur.execute("INSERT INTO \"user\" (user_id, username, email) VALUES (1, 'test_user', 'test@test.com') ON CONFLICT DO NOTHING;")
        
        # Yeni session oluştur ve ID'yi geri al
        query = "INSERT INTO session (user_id, start_time) VALUES (1, CURRENT_TIMESTAMP) RETURNING session_id;"
        cur.execute(query)
        new_id = cur.fetchone()[0]
        
        conn.commit()
        cur.close()
        print(f"✅ Yeni Oturum Başladı! ID: {new_id}")
        return {"session_id": new_id}
    except Exception as e:
        if conn: conn.rollback()
        print(f"❌ Oturum Başlatma Hatası: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if conn: conn.close()

# 2. VERİ KAYDETME KAPISI (Eksik olan ve 404 veren buydu!)
@app.post("/save-metrics")
async def save_metrics(data: GameMetricsData):
    conn = None
    try:
        conn = psycopg2.connect(DB_URL)
        cur = conn.cursor()
        
        # Gelen veriyi tabloya yazıyoruz
        query = """
        INSERT INTO game_metrics (session_id, score, reaction_time_ms, accuracy_rate) 
        VALUES (%s, %s, %s, %s)
        """
        cur.execute(query, (data.session_id, data.score, data.reaction_time_ms, data.accuracy_rate))
        
        conn.commit()
        cur.close()
        print(f"✅ Veri Kaydedildi - Session: {data.session_id}, Score: {data.score}")
        return {"status": "success"}
    except Exception as e:
        if conn: conn.rollback()
        print(f"❌ Kayıt Hatası: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if conn: conn.close()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)