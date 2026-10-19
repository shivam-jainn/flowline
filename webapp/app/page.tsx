"use client";
import { useEffect, useState, type CSSProperties } from "react";

export default function Home() {
  const [email, setEmail] = useState("");
  const [msg, setMsg] = useState<{ kind: "ok" | "err"; text: string } | null>(null);
  const [count, setCount] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);

  async function refreshCount() {
    try {
      const r = await fetch("/api/waitlist");
      const j = await r.json();
      if (typeof j.count === "number") setCount(j.count);
    } catch {
      /* ignore */
    }
  }

  useEffect(() => {
    // Mark JS as ready BEFORE hiding anything: CSS only hides .rv under .js,
    // so if React never hydrates the content stays visible.
    document.documentElement.classList.add("js");
    refreshCount();

    /* ── FAQ: one open at a time ── */
    const faqs = Array.from(document.querySelectorAll(".faq-list details"));
    const onToggle = (d: HTMLDetailsElement) => () => {
      if (d.open) {
        faqs.forEach((o) => {
          if (o !== d) (o as HTMLDetailsElement).open = false;
        });
      }
    };
    const cleanups: Array<() => void> = [];
    faqs.forEach((d) => {
      const el = d as HTMLDetailsElement;
      const fn = onToggle(el);
      el.addEventListener("toggle", fn);
      cleanups.push(() => el.removeEventListener("toggle", fn));
    });

    /* ── entrance reveals ── */
    const items = Array.from(document.querySelectorAll(".rv"));
    if (!("IntersectionObserver" in window)) {
      items.forEach((el) => el.classList.add("in"));
    } else {
      const io = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            if (entry.isIntersecting) {
              entry.target.classList.add("in");
              io.unobserve(entry.target);
            }
          });
        },
        { rootMargin: "0px 0px -8% 0px", threshold: 0.15 },
      );
      items.forEach((el) => io.observe(el));
      cleanups.push(() => io.disconnect());
    }

    return () => {
      cleanups.forEach((fn) => fn());
    };
  }, []);

  function toggleTheme() {
    const root = document.documentElement;
    const next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", next);
    root.style.colorScheme = next;
    try {
      localStorage.setItem("fl-theme", next);
    } catch {
      /* ignore */
    }
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setMsg(null);
    try {
      const r = await fetch("/api/waitlist", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ email, source: "flowline-landing" }),
      });
      const j = await r.json();
      if (!r.ok) {
        setMsg({ kind: "err", text: j.error ?? "Something went wrong." });
      } else if (j.duplicate) {
        setMsg({ kind: "ok", text: "You're already on the list. We'll be in touch." });
        refreshCount();
      } else {
        setMsg({ kind: "ok", text: "You're on the list. We'll be in touch." });
        setEmail("");
        refreshCount();
      }
    } catch {
      setMsg({ kind: "err", text: "Network error. Try again." });
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <a className="skip" href="#main">
        Skip to content
      </a>

      {/* ============ icon symbols (Flowline brand icon set) ============ */}
      <svg width="0" height="0" style={{ position: "absolute" }} aria-hidden="true">
        <symbol id="i-mark" viewBox="0 0 24 24">
          <path
            d="M4 18h5v-5h6V8h5"
            fill="none"
            stroke="currentColor"
            strokeWidth="2.25"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </symbol>
        <symbol id="i-capture" viewBox="0 0 24 24">
          <g
            fill="none"
            stroke="currentColor"
            strokeWidth="1.75"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M4 8.5V6.5A2.5 2.5 0 0 1 6.5 4h2" />
            <path d="M15.5 4h2A2.5 2.5 0 0 1 20 6.5v2" />
            <path d="M20 15.5v2a2.5 2.5 0 0 1-2.5 2.5h-2" />
            <path d="M8.5 20h-2A2.5 2.5 0 0 1 4 17.5v-2" />
            <circle cx="12" cy="12" r="3" />
          </g>
        </symbol>
        <symbol id="i-guide" viewBox="0 0 24 24">
          <g
            fill="none"
            stroke="currentColor"
            strokeWidth="1.75"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M7 3.5h6.5L18 8v12.5H7z" />
            <path d="M13.5 3.5V8H18" />
            <path d="M9.5 12.5h6M9.5 16h4" />
          </g>
        </symbol>
        <symbol id="i-publish" viewBox="0 0 24 24">
          <g
            fill="none"
            stroke="currentColor"
            strokeWidth="1.75"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M12 15.5V4" />
            <path d="M8 8l4-4 4 4" />
            <path d="M4.5 14.5v3a3 3 0 0 0 3 3h9a3 3 0 0 0 3-3v-3" />
          </g>
        </symbol>
        <symbol id="i-chevron" viewBox="0 0 24 24">
          <path
            d="M9.5 5l7 7-7 7"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.75"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </symbol>
        <symbol id="i-sun" viewBox="0 0 24 24">
          <g
            fill="none"
            stroke="currentColor"
            strokeWidth="1.75"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <circle cx="12" cy="12" r="4" />
            <path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M18.7 5.3l-1.4 1.4M6.7 17.3l-1.4 1.4" />
          </g>
        </symbol>
        <symbol id="i-moon" viewBox="0 0 24 24">
          <path
            d="M20 14.5A8.2 8.2 0 0 1 9.5 4 8.5 8.5 0 1 0 20 14.5z"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.75"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </symbol>
      </svg>

      <header className="site-head">
        <div className="wrap">
          <a className="lockup" href="#main" aria-label="Flowline home">
            <svg className="mark" viewBox="0 0 24 24" aria-hidden="true">
              <use href="#i-mark" />
            </svg>
            <span className="word">Flowline</span>
          </a>
          <nav className="nav-links" aria-label="Sections">
            <a href="#how">How it works</a>
            <a href="#product">Inside the product</a>
            <a href="#faq">FAQ</a>
          </nav>
          <button
            className="theme-toggle"
            type="button"
            onClick={toggleTheme}
            aria-label="Switch color theme"
            title="Switch color theme"
          >
            <svg className="od-icon i-moon" viewBox="0 0 24 24" aria-hidden="true">
              <use href="#i-moon" />
            </svg>
            <svg className="od-icon i-sun" viewBox="0 0 24 24" aria-hidden="true">
              <use href="#i-sun" />
            </svg>
          </button>
          <a className="btn btn-primary head-cta" href="#get-access">
            Get early access
            <svg className="od-icon nudge" viewBox="0 0 24 24" aria-hidden="true">
              <use href="#i-chevron" />
            </svg>
          </a>
        </div>
      </header>

      <main id="main">
        {/* ═══ HERO ═══ */}
        <section className="hero" aria-labelledby="heroTitle">
          <div className="wrap hero-grid">
            <div>
              <p className="eyebrow rv">Flowline for macOS</p>
              <h1 id="heroTitle">
                <span className="w" style={{ "--w": 0 } as CSSProperties}>
                  Turn
                </span>{" "}
                <span className="w" style={{ "--w": 1 } as CSSProperties}>
                  what
                </span>{" "}
                <span className="w" style={{ "--w": 2 } as CSSProperties}>
                  you
                </span>{" "}
                <span className="w" style={{ "--w": 3 } as CSSProperties}>
                  do
                </span>{" "}
                <span className="w" style={{ "--w": 4 } as CSSProperties}>
                  into
                </span>{" "}
                <span className="w" style={{ "--w": 5 } as CSSProperties}>
                  Guides.
                </span>
              </h1>
              <p className="lead rv" style={{ "--i": 2 } as CSSProperties}>
                Do a task once. Flowline writes it up as a guide.
              </p>
              <div className="hero-actions rv" style={{ "--i": 3 } as CSSProperties}>
                <form id="get-access" className="waitlist-form" onSubmit={submit}>
                  <input
                    type="email"
                    required
                    placeholder="you@example.com"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    aria-label="Email address"
                  />
                  <button className="btn btn-primary" disabled={busy} type="submit">
                    {busy ? "Joining…" : "Join waitlist"}
                  </button>
                </form>
                {msg && <p className={`form-msg ${msg.kind}`} role="status">{msg.text}</p>}
                {count !== null && <p className="form-count">{count} on the waitlist · One email, no spam.</p>}
              </div>
            </div>

            <div className="hero-visual rv" style={{ "--i": 2 } as CSSProperties}>
              <div
                className="win"
                role="img"
                aria-label="Flowline window showing a new project form; the Create project button is highlighted with an amber Halo ring and a captured step card floats beside it."
              >
                <div className="win-bar">
                  <span className="lights" aria-hidden="true">
                    <i></i>
                    <i></i>
                    <i></i>
                  </span>
                  <span className="win-title">Projects</span>
                </div>
                <div className="win-body">
                  <nav className="win-side" aria-hidden="true">
                    <p className="side-cap">Workspace</p>
                    <span className="side-item is-on">Projects</span>
                    <span className="side-item">Templates</span>
                    <span className="side-item">Archive</span>
                  </nav>
                  <div className="win-main">
                    <p className="win-h">New project</p>
                    <p className="win-sub">Name it now — you can change it later.</p>
                    <p className="win-label">Project name</p>
                    <div className="win-field">Website refresh</div>
                    <div className="win-cta-row">
                      <span className="win-cta">Create project</span>
                      <span className="halo" aria-hidden="true"></span>
                      <span className="cursor" aria-hidden="true">
                        <svg viewBox="0 0 18 22">
                          <path
                            d="M2.4 1.6v16.2l4.1-4 2.7 6.4 2.8-1.2-2.7-6.3h5.9z"
                            fill="#1D1D1F"
                            stroke="#FFFFFF"
                            strokeWidth="1.4"
                            strokeLinejoin="round"
                          />
                        </svg>
                      </span>
                    </div>
                  </div>
                </div>
              </div>

              <div className="float-card" aria-hidden="true">
                <span className="step-num">01 — CAPTURED</span>
                <p className="step-label">Click “Create project”</p>
                <div className="thumb">
                  <span className="bar w2"></span>
                  <span className="bar w1"></span>
                  <span className="chip">Create a new project</span>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* ═══ HOW IT WORKS ═══ */}
        <section className="how" id="how" aria-labelledby="howTitle">
          <div className="wrap">
            <div className="sec-head">
              <span className="ghost" aria-hidden="true">
                01
              </span>
              <p className="eyebrow rv">How it works</p>
              <h2 className="sec-title rv" id="howTitle" style={{ "--i": 1 } as CSSProperties}>
                Do it once. Get a guide.
              </h2>
              <p className="lead rv" style={{ "--i": 2 } as CSSProperties}>
                Flowline does the writing.
              </p>
            </div>

            <ol className="flow">
              <li className="flow-item rv" style={{ "--i": 0 } as CSSProperties}>
                <span className="flow-icon">
                  <svg className="od-icon" viewBox="0 0 24 24" aria-hidden="true">
                    <use href="#i-capture" />
                  </svg>
                </span>
                <span className="flow-no">01</span>
                <h3>Record</h3>
                <p>Do your task. Flowline watches your clicks.</p>
              </li>
              <li className="flow-item rv is-halo" style={{ "--i": 1 } as CSSProperties}>
                <span className="flow-icon">
                  <svg className="od-icon" viewBox="0 0 24 24" aria-hidden="true">
                    <use href="#i-guide" />
                  </svg>
                </span>
                <span className="flow-no">02</span>
                <h3>Guide</h3>
                <p>It writes the steps, with pictures. AI helps with the words.</p>
              </li>
              <li className="flow-item rv" style={{ "--i": 2 } as CSSProperties}>
                <span className="flow-icon">
                  <svg className="od-icon" viewBox="0 0 24 24" aria-hidden="true">
                    <use href="#i-publish" />
                  </svg>
                </span>
                <span className="flow-no">03</span>
                <h3>Share</h3>
                <p>Send a link. Anyone can follow along.</p>
              </li>
            </ol>
          </div>
        </section>

        {/* ═══ INSIDE THE PRODUCT ═══ */}
        <section className="product" id="product" aria-labelledby="prodTitle">
          <div className="wrap">
            <div className="sec-head">
              <span className="ghost" aria-hidden="true">
                02
              </span>
              <p className="eyebrow rv">Inside the product</p>
              <h2 className="sec-title rv" id="prodTitle" style={{ "--i": 1 } as CSSProperties}>
                An editor, an assistant, a reader.
              </h2>
              <p className="lead rv" style={{ "--i": 2 } as CSSProperties}>
                One guide, three views.
              </p>
            </div>

            {/* feature 1 — guide editor */}
            <article className="feature">
              <div className="copy rv">
                <p className="eyebrow">Guide editor</p>
                <h3>Edit like a document.</h3>
                <p>Rename, move, or delete any step.</p>
              </div>
              <div className="visual rv" style={{ "--i": 1 } as CSSProperties}>
                <div
                  className="mock"
                  role="img"
                  aria-label="Guide editor showing step 01 Open the Acme workspace with a horizontal step gutter below."
                >
                  <div className="mock-bar">Getting started on your Mac — Guide editor</div>
                  <div className="mock-body">
                    <p className="ed-title">Getting started on your Mac</p>
                    <div className="ed-step">
                      <span className="step-num">STEP 01</span>
                      <h4>Open the Acme workspace</h4>
                      <p>
                        Launch the workspace you were invited to. The home screen opens on your
                        morning briefing.
                      </p>
                    </div>
                    <div className="ed-gutter" aria-hidden="true">
                      <span className="g on">
                        <i></i>
                        <i></i>
                        <span>01</span>
                      </span>
                      <span className="g">
                        <i></i>
                        <i></i>
                        <span>02</span>
                      </span>
                      <span className="g">
                        <i></i>
                        <i></i>
                        <span>03</span>
                      </span>
                      <span className="g">
                        <i></i>
                        <i></i>
                        <span>04</span>
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </article>

            {/* feature 2 — AI refine */}
            <article className="feature flip">
              <div className="copy rv">
                <p className="eyebrow">AI refine</p>
                <h3>Fix the wording with AI.</h3>
                <p>AI rewrites steps in plain words. Your pictures stay as they are.</p>
              </div>
              <div className="visual rv" style={{ "--i": 1 } as CSSProperties}>
                <div
                  className="mock"
                  role="img"
                  aria-label="AI panel rewriting a step from Click create project to Create a new project, with the note Reworded the step, screenshot unchanged."
                >
                  <div className="mock-bar">AI — Connected</div>
                  <div className="mock-body">
                    <div className="ai-chips" aria-hidden="true">
                      <span className="c">Cleanup</span>
                      <span className="c">Explain</span>
                      <span className="c">Rewrite</span>
                      <span className="c">Convert</span>
                      <span className="c">Automation</span>
                    </div>
                    <div className="ai-block">
                      <p className="ai-from">Click create project</p>
                      <svg className="ai-arrow" viewBox="0 0 12 12" aria-hidden="true">
                        <path
                          d="M6 1.5v8M2.8 6.6 6 9.8l3.2-3.2"
                          fill="none"
                          stroke="currentColor"
                          strokeWidth="1.3"
                          strokeLinecap="round"
                          strokeLinejoin="round"
                        />
                      </svg>
                      <p className="ai-to">Create a new project</p>
                      <p className="ai-note">Reworded the step. Screenshot unchanged.</p>
                    </div>
                    <div className="ai-meta" aria-hidden="true">
                      <span className="pill">@step</span>
                      <span className="pill">Your own AI account</span>
                      <span className="pill">Works on your Mac</span>
                    </div>
                  </div>
                </div>
              </div>
            </article>

            {/* feature 3 — reader */}
            <article className="feature">
              <div className="copy rv">
                <p className="eyebrow">Reader view</p>
                <h3>Readers just read it.</h3>
                <p>Opens in any browser. Nothing to install.</p>
              </div>
              <div className="visual rv" style={{ "--i": 1 } as CSSProperties}>
                <div
                  className="mock"
                  role="img"
                  aria-label="Published guide Create a Project with three steps: Click Create project, Name the project, Choose a template."
                >
                  <div className="mock-bar">Reader — published guide</div>
                  <div className="mock-body">
                    <p className="rd-eyebrow">Guide · 3 steps · captured just now</p>
                    <p className="rd-title">Create a Project</p>
                    <div className="rd-list">
                      <div className="rd-item">
                        <span className="n">01</span>
                        <div>
                          <p className="t">Click “Create project”</p>
                          <p className="d">Create a new project from the Projects sidebar.</p>
                        </div>
                      </div>
                      <div className="rd-item">
                        <span className="n">02</span>
                        <div>
                          <p className="t">Name the project</p>
                          <p className="d">Type a name now — you can change it later.</p>
                        </div>
                      </div>
                      <div className="rd-item">
                        <span className="n">03</span>
                        <div>
                          <p className="t">Choose a template</p>
                          <p className="d">Pick Onboarding or start from Starter.</p>
                        </div>
                      </div>
                    </div>
                    <p className="rd-foot">Published with Flowline</p>
                  </div>
                </div>
              </div>
            </article>
          </div>
        </section>

        {/* ═══ FAQ ═══ */}
        <section className="faq" id="faq" aria-labelledby="faqTitle">
          <div className="wrap">
            <div className="sec-head">
              <span className="ghost" aria-hidden="true">
                03
              </span>
              <p className="eyebrow rv">FAQ</p>
              <h2 className="sec-title rv" id="faqTitle" style={{ "--i": 1 } as CSSProperties}>
                Questions.
              </h2>
              <p className="lead rv" style={{ "--i": 2 } as CSSProperties}>
                Short answers.
              </p>
            </div>

            <div className="faq-list rv" style={{ "--i": 2 } as CSSProperties}>
              <details>
                <summary>
                  What does Flowline record?
                  <svg className="od-icon" viewBox="0 0 24 24" aria-hidden="true">
                    <use href="#i-chevron" />
                  </svg>
                </summary>
                <p className="faq-a">Your clicks and typing — each with a screenshot.</p>
              </details>
              <details>
                <summary>
                  What do readers need?
                  <svg className="od-icon" viewBox="0 0 24 24" aria-hidden="true">
                    <use href="#i-chevron" />
                  </svg>
                </summary>
                <p className="faq-a">A browser. Nothing to install.</p>
              </details>
              <details>
                <summary>
                  Can I change a guide later?
                  <svg className="od-icon" viewBox="0 0 24 24" aria-hidden="true">
                    <use href="#i-chevron" />
                  </svg>
                </summary>
                <p className="faq-a">Yes. Any step, anytime.</p>
              </details>
            </div>
          </div>
        </section>
      </main>

      <footer className="site-foot">
        <div className="wrap">
          <div className="foot-grid">
            <div>
              <a className="lockup" href="#main" aria-label="Flowline home">
                <svg className="mark" viewBox="0 0 24 24" aria-hidden="true">
                  <use href="#i-mark" />
                </svg>
                <span className="word">Flowline</span>
              </a>
              <p className="foot-tag">Turn what you do into Guides.</p>
            </div>
            <nav className="foot-links" aria-label="Sections">
              <a href="#how">How it works</a>
              <a href="#product">Inside the product</a>
              <a href="#faq">FAQ</a>
              <a href="#get-access">Get early access</a>
            </nav>
          </div>
          <p className="foot-meta">Flowline for macOS · Version 1.0 · October 2026</p>
        </div>
      </footer>
    </>
  );
}
