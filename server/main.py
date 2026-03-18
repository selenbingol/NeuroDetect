from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import psycopg2
from pydantic import BaseModel

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1):\d+",
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_URL = "postgresql://neondb_owner:npg_y1YGSLtIZW0B@ep-rough-star-agysl1zm-pooler.c-2.eu-central-1.aws.neon.tech/neondb?sslmode=require"


class RegisterData(BaseModel):
    username: str
    email: str
    password_hash: str
    dob: str | None = None
    consent_status: bool = False
    role: str


class LoginData(BaseModel):
    username: str
    password_hash: str


class StartSessionData(BaseModel):
    user_id: int
    session_type: str = "game"


class EndSessionData(BaseModel):
    session_id: int


class GameMetricsData(BaseModel):
    session_id: int
    score: int
    reaction_time_ms: int
    accuracy_rate: float
    miss_count: int


@app.post("/register")
async def register(data: RegisterData):
    conn = None
    cur = None
    try:
        if data.role not in ["patient", "doctor"]:
            raise HTTPException(status_code=400, detail="Invalid role")

        conn = psycopg2.connect(DB_URL)
        cur = conn.cursor()

        query = """
        INSERT INTO public."user"
        (username, email, password_hash, dob, consent_status, role)
        VALUES (%s, %s, %s, %s, %s, %s)
        RETURNING user_id;
        """

        cur.execute(
            query,
            (
                data.username,
                data.email,
                data.password_hash,
                data.dob,
                data.consent_status,
                data.role,
            ),
        )

        user_id = cur.fetchone()[0]
        conn.commit()

        return {
            "user_id": user_id,
            "role": data.role,
            "status": "registered"
        }

    except HTTPException:
        raise
    except Exception as e:
        if conn:
            conn.rollback()
        print(f"❌ Register Hatası: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


@app.post("/login")
async def login(data: LoginData):
    conn = None
    cur = None
    try:
        conn = psycopg2.connect(DB_URL)
        cur = conn.cursor()

        query = """
        SELECT user_id, username, email, role
        FROM public."user"
        WHERE username = %s AND password_hash = %s;
        """
        cur.execute(query, (data.username, data.password_hash))
        row = cur.fetchone()

        if not row:
            raise HTTPException(status_code=401, detail="Invalid credentials")

        return {
            "user_id": row[0],
            "username": row[1],
            "email": row[2],
            "role": row[3],
        }

    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Login Hatası: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


@app.post("/start-session")
async def start_session(data: StartSessionData):
    conn = None
    cur = None
    try:
        conn = psycopg2.connect(DB_URL)
        cur = conn.cursor()

        query = """
        INSERT INTO public.session (user_id, start_time, end_time, session_type)
        VALUES (%s, CURRENT_TIMESTAMP, NULL, %s)
        RETURNING session_id;
        """
        cur.execute(query, (data.user_id, data.session_type))

        new_id = cur.fetchone()[0]
        conn.commit()

        print(f"✅ Yeni oturum başladı. ID: {new_id}")
        return {"session_id": new_id}

    except Exception as e:
        if conn:
            conn.rollback()
        print(f"❌ Oturum Başlatma Hatası: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


@app.post("/end-session")
async def end_session(data: EndSessionData):
    conn = None
    cur = None
    try:
        conn = psycopg2.connect(DB_URL)
        cur = conn.cursor()

        query = """
        UPDATE public.session
        SET end_time = CURRENT_TIMESTAMP
        WHERE session_id = %s
        RETURNING session_id;
        """
        cur.execute(query, (data.session_id,))
        row = cur.fetchone()

        if not row:
            raise HTTPException(status_code=404, detail="Session not found")

        conn.commit()

        print(f"✅ Oturum kapatıldı. ID: {data.session_id}")
        return {"status": "ended", "session_id": data.session_id}

    except HTTPException:
        raise
    except Exception as e:
        if conn:
            conn.rollback()
        print(f"❌ Oturum Kapatma Hatası: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


@app.post("/save-metrics")
async def save_metrics(data: GameMetricsData):
    conn = None
    cur = None
    try:
        conn = psycopg2.connect(DB_URL)
        cur = conn.cursor()

        query = """
        INSERT INTO public.game_metrics
        (session_id, score, reaction_time_ms, accuracy_rate, miss_count)
        VALUES (%s, %s, %s, %s, %s)
        RETURNING metric_id;
        """
        cur.execute(
            query,
            (
                data.session_id,
                data.score,
                data.reaction_time_ms,
                data.accuracy_rate,
                data.miss_count,
            ),
        )

        metric_id = cur.fetchone()[0]
        conn.commit()

        print(
            f"✅ Metric kaydedildi. metric_id={metric_id}, "
            f"session_id={data.session_id}, miss_count={data.miss_count}"
        )
        return {"status": "success", "metric_id": metric_id}

    except Exception as e:
        if conn:
            conn.rollback()
        print(f"❌ Kayıt Hatası: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()