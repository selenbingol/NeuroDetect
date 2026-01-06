import { useEffect, useMemo, useRef, useState } from "react";

/**
 * NeuroDetect Waiting Room Mini Game (MVP)
 * - Reaction Time + Attention (false click) test
 * - Measures: avg reaction time, accuracy, false clicks
 * - No DB / no API yet: results are shown and can be copied as JSON
 */

const PHASE = {
  START: "START",
  COUNTDOWN: "COUNTDOWN",
  WAITING: "WAITING",
  TARGET: "TARGET",
  RESULT: "RESULT",
};

function msNow() {
  return performance.now();
}

function clamp(n, min, max) {
  return Math.max(min, Math.min(max, n));
}

export default function App() {
  const [phase, setPhase] = useState(PHASE.START);

  // Config (keep simple for MVP)
  const rounds = 15; // total trials
  const falseTargetRate = 0.25; // 25% distractor trials
  const minWaitMs = 900;
  const maxWaitMs = 2200;
  const targetVisibleMs = 900; // time window to react

  // Game state
  const [currentRound, setCurrentRound] = useState(0);
  const [message, setMessage] = useState("");
  const [isFalseTarget, setIsFalseTarget] = useState(false);

  // Results collection
  const [reactionTimes, setReactionTimes] = useState([]); // only for correct target clicks
  const [hits, setHits] = useState(0); // correct target clicks in time
  const [misses, setMisses] = useState(0); // target not clicked in time
  const [falseClicks, setFalseClicks] = useState(0); // clicked when should not

  // Timing refs
  const targetShownAtRef = useRef(null);
  const waitTimerRef = useRef(null);
  const targetTimerRef = useRef(null);

  const accuracyRate = useMemo(() => {
    const totalTargetTrials = hits + misses; // only true target rounds
    if (totalTargetTrials === 0) return 0;
    return hits / totalTargetTrials;
  }, [hits, misses]);

  const avgReactionTimeMs = useMemo(() => {
    if (reactionTimes.length === 0) return 0;
    const sum = reactionTimes.reduce((a, b) => a + b, 0);
    return Math.round(sum / reactionTimes.length);
  }, [reactionTimes]);

  const resultJson = useMemo(() => {
    const nowIso = new Date().toISOString();
    return {
      user_id: "demo",
      game_type: "reaction_attention_v1",
      timestamp: nowIso,
      rounds_total: rounds,
      rounds_completed: currentRound,
      avg_reaction_time_ms: avgReactionTimeMs,
      accuracy_rate: Number(accuracyRate.toFixed(2)),
      false_clicks: falseClicks,
      hits,
      misses,
      reaction_times_ms: reactionTimes,
    };
  }, [
    accuracyRate,
    avgReactionTimeMs,
    currentRound,
    falseClicks,
    hits,
    misses,
    reactionTimes,
    rounds,
  ]);

  // Cleanup timers on unmount / phase changes
  useEffect(() => {
    return () => {
      if (waitTimerRef.current) clearTimeout(waitTimerRef.current);
      if (targetTimerRef.current) clearTimeout(targetTimerRef.current);
    };
  }, []);

  function resetGame() {
    setPhase(PHASE.START);
    setCurrentRound(0);
    setMessage("");
    setIsFalseTarget(false);

    setReactionTimes([]);
    setHits(0);
    setMisses(0);
    setFalseClicks(0);

    targetShownAtRef.current = null;

    if (waitTimerRef.current) clearTimeout(waitTimerRef.current);
    if (targetTimerRef.current) clearTimeout(targetTimerRef.current);
  }

  function startGame() {
    resetGame();
    setPhase(PHASE.COUNTDOWN);
    setMessage("Get ready...");
    // Short countdown, then first round
    setTimeout(() => {
      setMessage("");
      beginNextRound(1);
    }, 800);
  }

  function beginNextRound(nextRoundNumber) {
    // End condition
    if (nextRoundNumber > rounds) {
      setPhase(PHASE.RESULT);
      setMessage("Done.");
      return;
    }

    setCurrentRound(nextRoundNumber);
    setPhase(PHASE.WAITING);
    setMessage("Wait... (do not click)");

    // Decide trial type
    const isFalse = Math.random() < falseTargetRate;
    setIsFalseTarget(isFalse);

    // Random wait before showing something
    const waitMs = Math.floor(minWaitMs + Math.random() * (maxWaitMs - minWaitMs));
    waitTimerRef.current = setTimeout(() => {
      showTarget(isFalse);
    }, waitMs);
  }

  function showTarget(falseTrial) {
    setPhase(PHASE.TARGET);
    targetShownAtRef.current = msNow();

    if (falseTrial) {
      setMessage("BLUE appeared — do NOT click");
    } else {
      setMessage("GREEN appeared — CLICK!");
    }

    // If no click within window on TRUE target => miss
    targetTimerRef.current = setTimeout(() => {
      if (!falseTrial) {
        // true target not clicked in time
        setMisses((m) => m + 1);
      }
      // Proceed
      setMessage("");
      beginNextRound(currentRound + 1);
    }, targetVisibleMs);
  }

  function handleClick() {
    // Clicking rules depend on phase & trial type
    if (phase === PHASE.WAITING) {
      // clicked too early
      setFalseClicks((c) => c + 1);
      setMessage("Too early. Wait for the signal.");
      // keep waiting message after a short moment
      setTimeout(() => {
        if (phase === PHASE.WAITING) setMessage("Wait... (do not click)");
      }, 500);
      return;
    }

    if (phase !== PHASE.TARGET) return;

    // TARGET phase click
    if (targetTimerRef.current) clearTimeout(targetTimerRef.current);

    const shownAt = targetShownAtRef.current;
    const rt = shownAt ? Math.round(msNow() - shownAt) : null;

    if (isFalseTarget) {
      // should NOT click
      setFalseClicks((c) => c + 1);
      setMessage("Incorrect (false target).");
    } else {
      // correct click
      setHits((h) => h + 1);
      if (rt != null) setReactionTimes((arr) => [...arr, clamp(rt, 0, 5000)]);
      setMessage(rt != null ? `Good! Reaction: ${rt} ms` : "Good!");
    }

    // proceed to next round after short delay
    setTimeout(() => {
      setMessage("");
      beginNextRound(currentRound + 1);
    }, 450);
  }

  async function copyResults() {
    try {
      await navigator.clipboard.writeText(JSON.stringify(resultJson, null, 2));
      setMessage("Results copied to clipboard.");
      setTimeout(() => setMessage(""), 900);
    } catch {
      setMessage("Copy failed. Please select and copy manually.");
      setTimeout(() => setMessage(""), 1200);
    }
  }

  return (
    <div style={styles.page}>
      <div style={styles.card}>
        <div style={styles.header}>
          <div>
            <h1 style={styles.title}>NeuroDetect — Waiting Room Game</h1>
            <p style={styles.subtitle}>Reaction Time + Attention (MVP)</p>
          </div>
          <div style={styles.badge}>{phase}</div>
        </div>

        <div style={styles.statsRow}>
          <div style={styles.stat}>
            <div style={styles.statLabel}>Round</div>
            <div style={styles.statValue}>
              {phase === PHASE.RESULT ? rounds : currentRound}/{rounds}
            </div>
          </div>
          <div style={styles.stat}>
            <div style={styles.statLabel}>Avg RT</div>
            <div style={styles.statValue}>{avgReactionTimeMs ? `${avgReactionTimeMs} ms` : "-"}</div>
          </div>
          <div style={styles.stat}>
            <div style={styles.statLabel}>Accuracy</div>
            <div style={styles.statValue}>{hits + misses ? `${Math.round(accuracyRate * 100)}%` : "-"}</div>
          </div>
          <div style={styles.stat}>
            <div style={styles.statLabel}>False Clicks</div>
            <div style={styles.statValue}>{falseClicks}</div>
          </div>
        </div>

        <div
          onClick={handleClick}
          style={{
            ...styles.playArea,
            ...(phase === PHASE.TARGET
              ? isFalseTarget
                ? styles.falseTarget
                : styles.trueTarget
              : styles.waitArea),
          }}
          role="button"
          tabIndex={0}
        >
          <div style={styles.playText}>
            {phase === PHASE.START && "Press Start"}
            {phase === PHASE.COUNTDOWN && "Get ready..."}
            {phase === PHASE.WAITING && "WAIT"}
            {phase === PHASE.TARGET && (isFalseTarget ? "BLUE" : "GREEN")}
            {phase === PHASE.RESULT && "Finished"}
          </div>
        </div>

        {message && <div style={styles.message}>{message}</div>}

        <div style={styles.buttonsRow}>
          {phase === PHASE.START && (
            <button style={styles.primaryBtn} onClick={startGame}>
              Start
            </button>
          )}

          {phase !== PHASE.START && phase !== PHASE.RESULT && (
            <button style={styles.secondaryBtn} onClick={resetGame}>
              Reset
            </button>
          )}

          {phase === PHASE.RESULT && (
            <>
              <button style={styles.primaryBtn} onClick={startGame}>
                Play Again
              </button>
              <button style={styles.secondaryBtn} onClick={copyResults}>
                Copy Results (JSON)
              </button>
            </>
          )}
        </div>

        {phase === PHASE.RESULT && (
          <div style={styles.resultBox}>
            <div style={styles.resultTitle}>Result JSON (for integration later)</div>
            <pre style={styles.pre}>{JSON.stringify(resultJson, null, 2)}</pre>
          </div>
        )}
      </div>
    </div>
  );
}

const styles = {
  page: {
    minHeight: "100vh",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    padding: 18,
    background: "#0b1020",
    color: "#e9eefb",
    fontFamily:
      'ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, "Apple Color Emoji","Segoe UI Emoji"',
  },
  card: {
    width: "min(920px, 96vw)",
    background: "rgba(255,255,255,0.06)",
    border: "1px solid rgba(255,255,255,0.12)",
    borderRadius: 16,
    padding: 18,
    boxShadow: "0 12px 40px rgba(0,0,0,0.35)",
  },
  header: {
    display: "flex",
    alignItems: "flex-start",
    justifyContent: "space-between",
    gap: 12,
    marginBottom: 14,
  },
  title: { margin: 0, fontSize: 18, fontWeight: 700 },
  subtitle: { margin: "6px 0 0 0", opacity: 0.8, fontSize: 13 },
  badge: {
    fontSize: 12,
    padding: "6px 10px",
    borderRadius: 999,
    border: "1px solid rgba(255,255,255,0.18)",
    opacity: 0.9,
  },
  statsRow: {
    display: "grid",
    gridTemplateColumns: "repeat(4, minmax(0, 1fr))",
    gap: 10,
    marginBottom: 14,
  },
  stat: {
    padding: 12,
    borderRadius: 12,
    border: "1px solid rgba(255,255,255,0.12)",
    background: "rgba(255,255,255,0.04)",
  },
  statLabel: { fontSize: 12, opacity: 0.75, marginBottom: 6 },
  statValue: { fontSize: 16, fontWeight: 700 },
  playArea: {
    height: 260,
    borderRadius: 14,
    border: "1px solid rgba(255,255,255,0.14)",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    cursor: "pointer",
    userSelect: "none",
    marginBottom: 12,
  },
  playText: { fontSize: 28, fontWeight: 800, letterSpacing: 1 },
  waitArea: {
    background: "rgba(255,255,255,0.03)",
  },
  trueTarget: {
    background: "rgba(0, 200, 120, 0.35)",
  },
  falseTarget: {
    background: "rgba(80, 140, 255, 0.35)",
  },
  message: {
    minHeight: 22,
    fontSize: 13,
    opacity: 0.9,
    marginBottom: 10,
  },
  buttonsRow: { display: "flex", gap: 10, flexWrap: "wrap" },
  primaryBtn: {
    padding: "10px 14px",
    borderRadius: 12,
    border: "1px solid rgba(255,255,255,0.18)",
    background: "rgba(255,255,255,0.14)",
    color: "#e9eefb",
    cursor: "pointer",
    fontWeight: 700,
  },
  secondaryBtn: {
    padding: "10px 14px",
    borderRadius: 12,
    border: "1px solid rgba(255,255,255,0.18)",
    background: "transparent",
    color: "#e9eefb",
    cursor: "pointer",
    fontWeight: 700,
  },
  resultBox: {
    marginTop: 14,
    padding: 12,
    borderRadius: 12,
    border: "1px solid rgba(255,255,255,0.12)",
    background: "rgba(0,0,0,0.25)",
  },
  resultTitle: { fontSize: 12, opacity: 0.8, marginBottom: 8 },
  pre: {
    margin: 0,
    overflowX: "auto",
    fontSize: 12,
    lineHeight: 1.35,
  },
};
