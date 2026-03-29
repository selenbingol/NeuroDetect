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

@app.get("/patients/{user_id}/report")
async def get_patient_report(user_id: int):
    conn = None
    cur = None
    try:
        conn = psycopg2.connect(DB_URL)
        cur = conn.cursor()

        # Patient + patient profile
        cur.execute("""
            SELECT
                u.user_id,
                u.username,
                u.email,
                p.first_name,
                p.last_name,
                p.phone,
                p.address,
                p.dob,
                p.gender
            FROM public."user" u
            LEFT JOIN public.patients p ON u.user_id = p.user_id
            WHERE u.user_id = %s AND u.role = 'patient';
        """, (user_id,))
        patient = cur.fetchone()

        if not patient:
            raise HTTPException(status_code=404, detail="Patient not found")

        # Summary
        cur.execute("""
            SELECT
                COUNT(DISTINCT s.session_id) AS total_sessions,
                COALESCE(AVG(gm.score), 0),
                COALESCE(AVG(gm.accuracy_rate), 0),
                COALESCE(AVG(gm.reaction_time_ms), 0),
                COALESCE(SUM(gm.miss_count), 0)
            FROM public.session s
            LEFT JOIN public.game_metrics gm ON s.session_id = gm.session_id
            WHERE s.user_id = %s;
        """, (user_id,))
        summary = cur.fetchone()

        # Latest risk
        cur.execute("""
            SELECT
                ra.risk_score,
                ra.risk_level,
                ra.risk_alert,
                ra.assessment_time
            FROM public.risk_assessment ra
            JOIN public.session s ON ra.session_id = s.session_id
            WHERE s.user_id = %s
            ORDER BY ra.assessment_time DESC
            LIMIT 1;
        """, (user_id,))
        latest_risk = cur.fetchone()

        # Session history
        cur.execute("""
            SELECT
                s.session_id,
                s.start_time,
                s.end_time,
                gm.score,
                gm.accuracy_rate,
                gm.reaction_time_ms,
                gm.miss_count,
                ra.risk_score,
                ra.risk_level,
                ra.risk_alert,
                ra.assessment_time
            FROM public.session s
            LEFT JOIN public.game_metrics gm ON s.session_id = gm.session_id
            LEFT JOIN public.risk_assessment ra ON s.session_id = ra.session_id
            WHERE s.user_id = %s
            ORDER BY s.start_time DESC;
        """, (user_id,))
        sessions = cur.fetchall()

        return {
            "patient": {
                "user_id": patient[0],
                "username": patient[1],
                "email": patient[2],
                "first_name": patient[3],
                "last_name": patient[4],
                "phone": patient[5],
                "address": patient[6],
                "dob": None if patient[7] is None else str(patient[7]),
                "gender": patient[8],
            },
            "summary": {
                "total_sessions": summary[0],
                "avg_score": float(summary[1]),
                "avg_accuracy": float(summary[2]),
                "avg_reaction_time": float(summary[3]),
                "total_miss_count": int(summary[4]),
                "latest_risk_score": None if latest_risk is None else float(latest_risk[0]),
                "latest_risk_level": None if latest_risk is None else latest_risk[1],
                "latest_risk_alert": None if latest_risk is None else latest_risk[2],
                "latest_assessment_time": None if latest_risk is None or latest_risk[3] is None else str(latest_risk[3]),
            },
            "sessions": [
                {
                    "session_id": row[0],
                    "start_time": None if row[1] is None else str(row[1]),
                    "end_time": None if row[2] is None else str(row[2]),
                    "score": row[3],
                    "accuracy_rate": row[4],
                    "reaction_time_ms": row[5],
                    "miss_count": row[6],
                    "risk_score": None if row[7] is None else float(row[7]),
                    "risk_level": row[8],
                    "risk_alert": row[9],
                    "assessment_time": None if row[10] is None else str(row[10]),
                }
                for row in sessions
            ]
        }

    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Patient report hatası: {str(e)}")
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

@app.get("/patients")
async def get_patients():
    conn = None
    cur = None
    try:
        conn = psycopg2.connect(DB_URL)
        cur = conn.cursor()

        query = """
        SELECT
            u.user_id,
            p.first_name,
            p.last_name,
            p.dob,
            COALESCE(
                ARRAY_AGG(s.start_time ORDER BY s.start_time DESC)
                FILTER (WHERE s.start_time IS NOT NULL),
                ARRAY[]::timestamp[]
            ) AS session_dates
        FROM public."user" u
        LEFT JOIN public.patients p ON u.user_id = p.user_id
        LEFT JOIN public.session s ON u.user_id = s.user_id
        WHERE u.role = 'patient'
        GROUP BY u.user_id, p.first_name, p.last_name, p.dob
        ORDER BY p.first_name ASC, p.last_name ASC;
        """
        cur.execute(query)
        rows = cur.fetchall()

        return [
            {
                "user_id": row[0],
                "first_name": row[1] if row[1] else "",
                "last_name": row[2] if row[2] else "",
                "dob": None if row[3] is None else str(row[3]),
                "session_dates": [str(dt) for dt in row[4]] if row[4] else []
            }
            for row in rows
        ]

    except Exception as e:
        print(f"❌ Patients çekme hatası: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()

@app.get("/patients/{user_id}/report")
async def get_patient_report(user_id: int):
    conn = None
    cur = None
    try:
        conn = psycopg2.connect(DB_URL)
        cur = conn.cursor()

        # Patient info
        cur.execute("""
            SELECT user_id, username, email
            FROM public."user"
            WHERE user_id = %s AND role = 'patient';
        """, (user_id,))
        patient = cur.fetchone()

        if not patient:
            raise HTTPException(status_code=404, detail="Patient not found")

        # Summary stats
        cur.execute("""
            SELECT
                COUNT(DISTINCT s.session_id) AS total_sessions,
                COALESCE(AVG(gm.score), 0),
                COALESCE(AVG(gm.accuracy_rate), 0),
                COALESCE(AVG(gm.reaction_time_ms), 0),
                COALESCE(SUM(gm.miss_count), 0)
            FROM public.session s
            LEFT JOIN public.game_metrics gm ON s.session_id = gm.session_id
            WHERE s.user_id = %s;
        """, (user_id,))
        summary = cur.fetchone()

        # Session history
        cur.execute("""
            SELECT
                s.session_id,
                s.start_time,
                s.end_time,
                gm.score,
                gm.accuracy_rate,
                gm.reaction_time_ms,
                gm.miss_count
            FROM public.session s
            LEFT JOIN public.game_metrics gm ON s.session_id = gm.session_id
            WHERE s.user_id = %s
            ORDER BY s.start_time DESC;
        """, (user_id,))
        sessions = cur.fetchall()

        return {
            "patient": {
                "user_id": patient[0],
                "username": patient[1],
                "email": patient[2],
            },
            "summary": {
                "total_sessions": summary[0],
                "avg_score": float(summary[1]),
                "avg_accuracy": float(summary[2]),
                "avg_reaction_time": float(summary[3]),
                "total_miss_count": int(summary[4]),
            },
            "sessions": [
                {
                    "session_id": row[0],
                    "start_time": None if row[1] is None else str(row[1]),
                    "end_time": None if row[2] is None else str(row[2]),
                    "score": row[3],
                    "accuracy_rate": row[4],
                    "reaction_time_ms": row[5],
                    "miss_count": row[6],
                }
                for row in sessions
            ]
        }

    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Patient report hatası: {str(e)}")
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