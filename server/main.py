from fastapi import Depends, FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
import psycopg2
from pydantic import BaseModel
from fusion_engine import calculate_digital_risk
from multimodal_fusion import run_full_assessment
from sqlalchemy import create_engine, text
import httpx

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1):\d+",
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

DB_URL = "postgresql://neondb_owner:npg_y1YGSLtIZW0B@ep-rough-star-agysl1zm-pooler.c-2.eu-central-1.aws.neon.tech/neondb?sslmode=require"
engine = create_engine(DB_URL)

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


class StartSessionRequest(BaseModel):
    user_id: int
    session_type: str


class GameMetricsData(BaseModel):
    session_id: int
    score: int
    reaction_time_ms: int
    accuracy_rate: float
    tap_count: int = 0
    false_start_count: int = 0
    wrong_tap_count: int = 0
    timeout_count: int = 0
    false_alarm_count: int = 0
    omission_count: int = 0
    miss_count: int = 0


class SensorMetricsData(BaseModel):
    session_id: int
    avg_motion: float | None = None
    avg_gyro: float | None = None
    tremor_index: float | None = None
    movement_variability: float | None = None
    path_correction_count: int = 0
    sample_count: int = 0


class TargetMovementMetricsData(BaseModel):
    session_id: int
    slice_hit_count: int = 0
    slice_miss_count: int = 0
    successful_cut_count: int = 0
    near_miss_count: int = 0
    avg_slice_length: float | None = None
    avg_cut_coverage: float | None = None

class VisualMemoryMetricsData(BaseModel):
    session_id: int

    total_rounds: int = 8
    grid_item_count: int = 9
    changed_card_count: int = 3

    correct_selection_count: int = 0
    false_selection_count: int = 0
    omission_count: int = 0
    false_start_count: int = 0

    total_targets: int = 0
    total_misses: int = 0

    avg_reaction_time_ms: float | None = None
    accuracy_rate: float = 0
    memory_score: int = 0

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
async def start_session(data: StartSessionRequest):
    conn = None
    cur = None
    try:
        conn = psycopg2.connect(DB_URL)
        cur = conn.cursor()

        query = """
        INSERT INTO public.session (user_id, start_time, session_type)
        VALUES (%s, NOW(), %s)
        RETURNING session_id;
        """
        cur.execute(query, (data.user_id, data.session_type))
        session_id = cur.fetchone()[0]
        conn.commit()

        return {
            "session_id": session_id,
            "user_id": data.user_id,
            "session_type": data.session_type,
            "message": "Session started successfully"
        }

    except Exception as e:
        if conn:
            conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


@app.post("/end-session")
async def end_session(data: EndSessionData, background_tasks: BackgroundTasks):
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

        # Oturum kapandıktan sonra arka planda fusion değerlendirmesi başlat
        background_tasks.add_task(_trigger_fusion_background, data.session_id)

        print(f"✅ Oturum kapatıldı. ID: {data.session_id} — Fusion arka planda başlatıldı.")
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


async def _trigger_fusion_background(session_id: int):
    """
    Oturum kapandıktan sonra arka planda çalışır.
    /api/fusion/assess/{session_id} endpoint'ini dahili olarak çağırarak
    fusion değerlendirmesini hesaplar ve fusion_assessment tablosuna kaydeder.
    Flutter uygulamasının ayrıca fusion çağrısı yapmasına gerek kalmaz.
    """
    try:
        # Oyun verilerinin DB'ye yazılması için kısa bekleme
        import asyncio
        await asyncio.sleep(1.5)

        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.get(
                f"http://127.0.0.1:8000/api/fusion/assess/{session_id}"
            )
            if resp.status_code == 200:
                print(f"✅ Arka plan fusion tamamlandı. session_id={session_id}")
            else:
                print(f"⚠️  Arka plan fusion başarısız. session_id={session_id} status={resp.status_code}")
    except Exception as e:
        print(f"⚠️  Arka plan fusion hatası. session_id={session_id}: {e}")


@app.post("/save-metrics")
async def save_metrics(data: GameMetricsData):
    conn = None
    cur = None
    try:
        conn = psycopg2.connect(DB_URL)
        cur = conn.cursor()

        miss_count_calc = (
            data.false_start_count
            + data.wrong_tap_count
            + data.timeout_count
            + data.false_alarm_count
            + data.omission_count
        )

        query = """
        INSERT INTO public.game_metrics
        (session_id, score, reaction_time_ms, accuracy_rate,
         tap_count, false_start_count, wrong_tap_count,
         timeout_count, false_alarm_count, omission_count, miss_count)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        RETURNING metric_id;
        """
        cur.execute(
            query,
            (
                data.session_id,
                data.score,
                data.reaction_time_ms,
                data.accuracy_rate,
                data.tap_count,
                data.false_start_count,
                data.wrong_tap_count,
                data.timeout_count,
                data.false_alarm_count,
                data.omission_count,
                miss_count_calc,
            ),
        )

        metric_id = cur.fetchone()[0]
        conn.commit()

        print(f"✅ Metric kaydedildi. metric_id={metric_id}, session_id={data.session_id}")
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


@app.post("/save-sensor-metrics")
async def save_sensor_metrics(data: SensorMetricsData):
    conn = None
    cur = None
    try:
        conn = psycopg2.connect(DB_URL)
        cur = conn.cursor()

        query = """
        INSERT INTO public.sensor_metrics
        (session_id, avg_motion, avg_gyro, tremor_index,
         movement_variability, path_correction_count, sample_count)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        RETURNING sensor_metric_id;
        """
        cur.execute(
            query,
            (
                data.session_id,
                data.avg_motion,
                data.avg_gyro,
                data.tremor_index,
                data.movement_variability,
                data.path_correction_count,
                data.sample_count,
            ),
        )

        sensor_metric_id = cur.fetchone()[0]
        conn.commit()

        print(
            f"✅ Sensor metric kaydedildi. sensor_metric_id={sensor_metric_id}, session_id={data.session_id}"
        )
        return {"status": "success", "sensor_metric_id": sensor_metric_id}

    except Exception as e:
        if conn:
            conn.rollback()
        print(f"❌ Sensor metric kayıt hatası: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


@app.post("/save-target-movement-metrics")
async def save_target_movement_metrics(data: TargetMovementMetricsData):
    conn = None
    cur = None
    try:
        conn = psycopg2.connect(DB_URL)
        cur = conn.cursor()

        query = """
        INSERT INTO public.target_movement_metrics
        (session_id, slice_hit_count, slice_miss_count, successful_cut_count,
         near_miss_count, avg_slice_length, avg_cut_coverage)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        RETURNING target_metric_id;
        """
        cur.execute(
            query,
            (
                data.session_id,
                data.slice_hit_count,
                data.slice_miss_count,
                data.successful_cut_count,
                data.near_miss_count,
                data.avg_slice_length,
                data.avg_cut_coverage,
            ),
        )

        target_metric_id = cur.fetchone()[0]
        conn.commit()

        print(
            f"✅ Target movement metric kaydedildi. target_metric_id={target_metric_id}, session_id={data.session_id}"
        )
        return {"status": "success", "target_metric_id": target_metric_id}

    except Exception as e:
        if conn:
            conn.rollback()
        print(f"❌ Target movement metric kayıt hatası: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()

@app.post("/save-visual-memory-metrics")
async def save_visual_memory_metrics(data: VisualMemoryMetricsData):
    conn = None
    cur = None
    try:
        conn = psycopg2.connect(DB_URL)
        cur = conn.cursor()

        total_targets_calc = (
            data.total_targets
            if data.total_targets > 0
            else data.total_rounds * data.changed_card_count
        )

        total_misses_calc = (
            data.total_misses
            if data.total_misses > 0
            else data.false_selection_count + data.omission_count
        )

        query = """
        INSERT INTO public.visual_memory_metrics
        (
            session_id,
            total_rounds,
            grid_item_count,
            changed_card_count,
            correct_selection_count,
            false_selection_count,
            omission_count,
            false_start_count,
            total_targets,
            total_misses,
            avg_reaction_time_ms,
            accuracy_rate,
            memory_score
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (session_id)
        DO UPDATE SET
            total_rounds = EXCLUDED.total_rounds,
            grid_item_count = EXCLUDED.grid_item_count,
            changed_card_count = EXCLUDED.changed_card_count,
            correct_selection_count = EXCLUDED.correct_selection_count,
            false_selection_count = EXCLUDED.false_selection_count,
            omission_count = EXCLUDED.omission_count,
            false_start_count = EXCLUDED.false_start_count,
            total_targets = EXCLUDED.total_targets,
            total_misses = EXCLUDED.total_misses,
            avg_reaction_time_ms = EXCLUDED.avg_reaction_time_ms,
            accuracy_rate = EXCLUDED.accuracy_rate,
            memory_score = EXCLUDED.memory_score,
            completed_at = CURRENT_TIMESTAMP
        RETURNING visual_memory_metric_id;
        """

        cur.execute(
            query,
            (
                data.session_id,
                data.total_rounds,
                data.grid_item_count,
                data.changed_card_count,
                data.correct_selection_count,
                data.false_selection_count,
                data.omission_count,
                data.false_start_count,
                total_targets_calc,
                total_misses_calc,
                data.avg_reaction_time_ms,
                data.accuracy_rate,
                data.memory_score,
            ),
        )

        visual_memory_metric_id = cur.fetchone()[0]
        conn.commit()

        print(
            f"✅ Visual memory metric kaydedildi. "
            f"visual_memory_metric_id={visual_memory_metric_id}, session_id={data.session_id}"
        )

        return {
            "status": "success",
            "visual_memory_metric_id": visual_memory_metric_id
        }

    except Exception as e:
        if conn:
            conn.rollback()
        print(f"❌ Visual memory metric kayıt hatası: {str(e)}")
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
            p.phone,
            p.gender,
            COALESCE(
                ARRAY_AGG(s.start_time ORDER BY s.start_time DESC)
                FILTER (WHERE s.start_time IS NOT NULL),
                ARRAY[]::timestamp[]
            ) AS session_dates
        FROM public."user" u
        LEFT JOIN public.patients p ON u.user_id = p.user_id
        LEFT JOIN public.session s ON u.user_id = s.user_id
        WHERE u.role = 'patient'
        GROUP BY
            u.user_id,
            p.first_name,
            p.last_name,
            p.dob,
            p.phone,
            p.gender
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
                "phone": row[4] if row[4] else "",
                "gender": row[5] if row[5] else "",
                "session_dates": [str(dt) for dt in row[6]] if row[6] else []
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

        cur.execute("""
            SELECT user_id, username, email
            FROM public."user"
            WHERE user_id = %s AND role = 'patient';
        """, (user_id,))
        patient = cur.fetchone()

        if not patient:
            raise HTTPException(status_code=404, detail="Patient not found")

        cur.execute("""
            SELECT
                COUNT(DISTINCT s.session_id) AS total_sessions,
                COALESCE(AVG(gm.score), 0),
                COALESCE(AVG(gm.accuracy_rate), 0),
                COALESCE(AVG(gm.reaction_time_ms), 0),
                COALESCE(SUM(
                    COALESCE(gm.false_start_count, 0) +
                    COALESCE(gm.wrong_tap_count, 0) +
                    COALESCE(gm.timeout_count, 0) +
                    COALESCE(gm.false_alarm_count, 0) +
                    COALESCE(gm.omission_count, 0)
                ), 0),
                COALESCE(AVG(sm.avg_motion), 0),
                COALESCE(AVG(sm.avg_gyro), 0),
                COALESCE(AVG(sm.tremor_index), 0),

                COALESCE(AVG(vm.accuracy_rate), 0),
                COALESCE(AVG(vm.memory_score), 0),
                COALESCE(AVG(vm.avg_reaction_time_ms), 0)
            FROM public.session s
            LEFT JOIN public.game_metrics gm ON s.session_id = gm.session_id
            LEFT JOIN public.sensor_metrics sm ON s.session_id = sm.session_id
            LEFT JOIN public.visual_memory_metrics vm ON s.session_id = vm.session_id
            WHERE s.user_id = %s;
        """, (user_id,))
        summary = cur.fetchone()

        cur.execute("""
            SELECT
                s.session_id,
                s.start_time,
                s.end_time,
                s.session_type,

                gm.score,
                gm.accuracy_rate,
                gm.reaction_time_ms,
                gm.tap_count,
                gm.false_start_count,
                gm.wrong_tap_count,
                gm.timeout_count,
                gm.false_alarm_count,
                gm.omission_count,

                sm.avg_motion,
                sm.avg_gyro,
                sm.tremor_index,
                sm.movement_variability,
                sm.path_correction_count,
                sm.sample_count,

                tm.slice_hit_count,
                tm.slice_miss_count,
                tm.successful_cut_count,
                tm.near_miss_count,
                tm.avg_slice_length,
                tm.avg_cut_coverage,

                vm.total_rounds,
                vm.grid_item_count,
                vm.changed_card_count,
                vm.correct_selection_count,
                vm.false_selection_count,
                vm.omission_count AS visual_omission_count,
                vm.false_start_count AS visual_false_start_count,
                vm.total_targets,
                vm.total_misses,
                vm.avg_reaction_time_ms AS visual_avg_reaction_time_ms,
                vm.accuracy_rate AS visual_accuracy_rate,
                vm.memory_score

            FROM public.session s
            LEFT JOIN public.game_metrics gm ON s.session_id = gm.session_id
            LEFT JOIN public.sensor_metrics sm ON s.session_id = sm.session_id
            LEFT JOIN public.target_movement_metrics tm ON s.session_id = tm.session_id
            LEFT JOIN public.visual_memory_metrics vm ON s.session_id = vm.session_id
            WHERE s.user_id = %s
            ORDER BY s.start_time DESC;
        """, (user_id,))
        sessions = cur.fetchall()

        result = {
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
                "avg_motion": float(summary[5]),
                "avg_gyro": float(summary[6]),
                "avg_tremor_index": float(summary[7]),

                "avg_visual_memory_accuracy": float(summary[8]),
                "avg_memory_score": float(summary[9]),
                "avg_visual_memory_reaction_time": float(summary[10]),
            },
            "sessions": [
                {
                    "session_id": row[0],
                    "start_time": None if row[1] is None else str(row[1]),
                    "end_time": None if row[2] is None else str(row[2]),
                    "session_type": row[3],

                    "score": row[4],
                    "accuracy_rate": row[5],
                    "reaction_time_ms": row[6],
                    "tap_count": row[7],
                    "false_start_count": row[8],
                    "wrong_tap_count": row[9],
                    "timeout_count": row[10],
                    "false_alarm_count": row[11],
                    "omission_count": row[12],
                    "miss_count": (row[8] or 0) + (row[9] or 0) + (row[10] or 0) + (row[11] or 0) + (row[12] or 0),

                    "avg_motion": row[13],
                    "avg_gyro": row[14],
                    "tremor_index": row[15],
                    "movement_variability": row[16],
                    "path_correction_count": row[17],
                    "sample_count": row[18],

                    "slice_hit_count": row[19],
                    "slice_miss_count": row[20],
                    "successful_cut_count": row[21],
                    "near_miss_count": row[22],
                    "avg_slice_length": row[23],
                    "avg_cut_coverage": row[24],
                    
                    "visual_total_rounds": row[25],
                    "visual_grid_item_count": row[26],
                    "visual_changed_card_count": row[27],
                    "visual_correct_selection_count": row[28],
                    "visual_false_selection_count": row[29],
                    "visual_omission_count": row[30],
                    "visual_false_start_count": row[31],
                    "visual_total_targets": row[32],
                    "visual_total_misses": row[33],
                    "visual_avg_reaction_time_ms": row[34],
                    "visual_accuracy_rate": row[35],
                    "visual_memory_score": row[36],
                }
                for row in sessions
            ]
        }

        return result

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

@app.get("/api/fusion/assess/{session_id}")
def get_fusion_assessment(session_id: int):
    """
    3 katmanlı multimodal füzyon değerlendirmesi:
      Katman 1 — Dijital Fenotip (cognitive/motor risk)
      Katman 2 — Klinik Proxy (Alzheimer/ALS olasılıkları)
      Katman 3 — Nihai Füzyon + XAI Açıklama

    Sonuç hesaplandıktan sonra fusion_assessment tablosuna kaydedilir.
    """
    try:
        with engine.connect() as db:
            game_obj = db.execute(
                text("SELECT * FROM game_metrics WHERE session_id = :sid"),
                {"sid": session_id},
            ).mappings().first()
            target_obj = db.execute(
                text("SELECT * FROM target_movement_metrics WHERE session_id = :sid"),
                {"sid": session_id},
            ).mappings().first()
            memory_obj = db.execute(
                text("SELECT * FROM visual_memory_metrics WHERE session_id = :sid"),
                {"sid": session_id},
            ).mappings().first()
            sensor_obj = db.execute(
                text("SELECT * FROM sensor_metrics WHERE session_id = :sid"),
                {"sid": session_id},
            ).mappings().first()

            game_data = dict(game_obj) if game_obj else {}
            target_data = dict(target_obj) if target_obj else {}
            memory_data = dict(memory_obj) if memory_obj else {}
            sensor_data = dict(sensor_obj) if sensor_obj else {}

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Veritabanı hatası: {str(e)}")

    # 3 katmanlı multimodal füzyon pipeline
    result = run_full_assessment(
        session_id=session_id,
        game_data=game_data,
        target_data=target_data,
        memory_data=memory_data,
        sensor_data=sensor_data,
    )

    # Sonucu fusion_assessment tablosuna kaydet (UPSERT)
    try:
        import json as _json
        clinical = result.get("clinical_indicators", {})

        with engine.connect() as db:
            db.execute(text("""
                INSERT INTO public.fusion_assessment (
                    session_id,
                    cognitive_risk, motor_risk, digital_risk_score,
                    alzheimer_probability, alzheimer_risk_level, alzheimer_concern_score,
                    als_probability, als_risk_level, als_concern_score,
                    final_fusion_score, risk_level,
                    xai_explanation, dominant_factors,
                    assessed_at
                ) VALUES (
                    :session_id,
                    :cognitive_risk, :motor_risk, :digital_risk_score,
                    :alz_prob, :alz_level, :alz_concern,
                    :als_prob, :als_level, :als_concern,
                    :final_score, :risk_level,
                    :xai, :factors,
                    CURRENT_TIMESTAMP
                )
                ON CONFLICT (session_id) DO UPDATE SET
                    cognitive_risk      = EXCLUDED.cognitive_risk,
                    motor_risk          = EXCLUDED.motor_risk,
                    digital_risk_score  = EXCLUDED.digital_risk_score,
                    alzheimer_probability   = EXCLUDED.alzheimer_probability,
                    alzheimer_risk_level    = EXCLUDED.alzheimer_risk_level,
                    alzheimer_concern_score = EXCLUDED.alzheimer_concern_score,
                    als_probability         = EXCLUDED.als_probability,
                    als_risk_level          = EXCLUDED.als_risk_level,
                    als_concern_score       = EXCLUDED.als_concern_score,
                    final_fusion_score  = EXCLUDED.final_fusion_score,
                    risk_level          = EXCLUDED.risk_level,
                    xai_explanation     = EXCLUDED.xai_explanation,
                    dominant_factors    = EXCLUDED.dominant_factors,
                    assessed_at         = CURRENT_TIMESTAMP;
            """), {
                "session_id": session_id,
                "cognitive_risk": result.get("cognitive_risk", 0),
                "motor_risk": result.get("motor_risk", 0),
                "digital_risk_score": result.get("digital_risk_score", 0),
                "alz_prob": clinical.get("alzheimer_probability", 0),
                "alz_level": clinical.get("alzheimer_risk_level", "low"),
                "alz_concern": clinical.get("alzheimer_concern_score", 0),
                "als_prob": clinical.get("als_probability", 0),
                "als_level": clinical.get("als_risk_level", "low"),
                "als_concern": clinical.get("als_concern_score", 0),
                "final_score": result.get("final_fusion_score", 0),
                "risk_level": result.get("risk_level", "low"),
                "xai": result.get("xai_explanation", ""),
                "factors": _json.dumps(result.get("dominant_factors", [])),
            })
            db.commit()

        print(f"✅ Fusion assessment kaydedildi. session_id={session_id}")

    except Exception as e:
        print(f"⚠️ Fusion assessment DB kaydı başarısız (sonuç yine döner): {str(e)}")

    return {"status": "success", **result}


@app.get("/api/fusion/trend/{user_id}")
def get_fusion_trend(user_id: int):
    """
    Bir hastanın TÜM oturumları için fusion risk skorlarını tek çağrıda döner.
    Veriler fusion_assessment tablosundan okunur (önceden hesaplanmış).
    """
    try:
        with engine.connect() as db:
            rows = db.execute(text("""
                SELECT
                    fa.session_id,
                    s.start_time   AS date,
                    s.session_type,
                    fa.cognitive_risk,
                    fa.motor_risk,
                    fa.final_fusion_score AS overall_risk,
                    fa.alzheimer_probability,
                    fa.als_probability,
                    fa.risk_level
                FROM public.fusion_assessment fa
                JOIN public.session s ON fa.session_id = s.session_id
                WHERE s.user_id = :uid
                ORDER BY s.start_time ASC;
            """), {"uid": user_id}).mappings().all()

        trend_points = [
            {
                "session_id": row["session_id"],
                "date": str(row["date"]) if row["date"] else None,
                "session_type": row["session_type"],
                "cognitive_risk": float(row["cognitive_risk"] or 0),
                "motor_risk": float(row["motor_risk"] or 0),
                "overall_risk": float(row["overall_risk"] or 0),
                "alzheimer_probability": float(row["alzheimer_probability"] or 0),
                "als_probability": float(row["als_probability"] or 0),
                "risk_level": row["risk_level"],
            }
            for row in rows
        ]

        return {
            "status": "success",
            "user_id": user_id,
            "trend": trend_points,
        }

    except Exception as e:
        print(f"❌ Fusion trend hatası: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Fusion trend hatası: {str(e)}")