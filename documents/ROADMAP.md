# TN9K HDMI Project Roadmap

A structured plan for evolving the Tang Nano 9K HDMI core from a demo-oriented design into a more feature-complete, reusable, and standards-aligned HDMI subsystem.

---
## 1. Vision

Deliver an open, lightweight HDMI transmitter IP for small FPGAs that:

- Supports multiple standard resolutions and refresh rates.
- Provides reliable audio (48 kHz initially, extendable to 96 kHz / 192 kHz).
- Offers clean parameterization (generics) for reuse in other projects.
- Includes simulation + formal collateral for confidence and portability.
- Remains resource-conscious for GW1NR-class devices.

---
 
## 2. Current Status (Baseline After Recent Work)

| Area | Status | Notes |
|------|--------|-------|
| Video (640x480@60) | Stable | TMDS pipeline functional @ 25.2 MHz variant |
| TMDS Encoder | Pipelining optional | Generic `PIPELINE_BALANCE` added |
| Audio (48 kHz) | Stable with VIC20Nano | Fixed packet infrastructure, registered TERC4 inputs |
| ACR | Stable per frame | N/CTS generation working correctly with 48 kHz timing |
| Data Islands | Basic ASP + ACR | No InfoFrames / checksum compliance tightening |
| Constraints | Primary + generated clocks | HDMI outputs false-pathed; could refine |
| Docs | Updated README | Now needs spec compliance guidance |
| Tests / Simulation | Missing | No automated testbench yet |
| Parameterization | Limited | Hard-coded timings & frequencies |

---
 
## 3. Roadmap Summary

| Phase | Theme | Primary Outcomes | Target Difficulty |
|-------|-------|------------------|------------------|
| P1 | ✅ Compliance Foundations | Full 640x480 timing correctness, stable audio | COMPLETED |
| P2 | Robust Audio | 800 LPCM samples/frame scheduling, InfoFrames | Medium |
| P3 | Parameterization & Multi-Mode | Support 800x600, 720p (optionally 1024x768) | Med/High |
| P4 | Tooling & Verification | Simulation benches, lint, waveform reference sets | Medium |
| P5 | Interface & Extensibility | AXI-lite / simple bus config, pattern plug-ins | Medium |
| P6 | Performance Expansion | Higher pixel clocks w/ pipelined TMDS, 8/10/12-bit color | High |
| P7 | Advanced (Optional) | EDID read, DDC I²C, AVI / Audio InfoFrames, adaptive PLL | High |

---
 
## 4. Detailed Milestones

### Phase 1 – ✅ Compliance Foundations (COMPLETED)

- [✅] **Fixed audio infrastructure** with VIC20Nano packet system
- [✅] **Resolved synthesis errors** by replacing large sparse arrays with case statements
- [✅] **Added TERC4 signal stability** with registered inputs
- [✅] **Stable video + audio output** at 640x480@60Hz with 48 kHz audio
- [✅] **Optimized codebase** by removing unused files and components

**Next Steps for Enhanced Compliance:**
- [ ] Adjust ACR cadence (verify N / CTS math for 25.200 MHz variant & exact 25.175 mode)
- [ ] Allow switching to exact 25.175 MHz (alternate PLL config path + generic)
- [ ] Add guard band & packet timing assertions (simulation only initially)
- [ ] Replace single ACR-per-frame logic with spec-based interval (every 128 lines per HDMI 1.4)
- [ ] Add build-time generic: `PIXEL_CLOCK_MODE` (EXACT_25_175 | DERIVED_25_200)

### Phase 2 – Robust Audio

- [ ] Implement true packet budgeting: compute required ASP count = samples_per_frame / samples_per_packet.
- [ ] Pack two audio samples per packet where legal (channel status fields optional stub).
- [ ] Add Audio InfoFrame (type 0x84) minimal structure (even if not strictly required for 2-ch PCM on many sinks).
- [ ] CRC / checksum generation for InfoFrames.
- [ ] Monitoring counters: underrun/overrun FIFO flags exported for debug.

### Phase 3 – Multi-Mode Timing Support

- [ ] Abstract timing generator: record-based timing structure (porches, sync width, active, polarity).
- [ ] Provide predefined modes: 640x480, 800x600, 1024x768, 1280x720.
- [ ] Add generic `VIDEO_MODE` or loadable timing record.
- [ ] Auto-select correct N/CTS for new pixel clock (table-driven method).
- [ ] Optional dynamic mode switch handshake (requiring blanking window).

### Phase 4 – Verification & Tooling

- [ ] Add VHDL testbench with:
  - Deterministic pattern source
  - TMDS encoder reference model (Python or behavioral VHDL)
  - Packet sequence logger
- [ ] Add waveform capture scripts (e.g., GHDL + GTKWave batch config).
- [ ] Basic formal (if toolchain available) for counters: no overflow, legal ranges.
- [ ] Lint (GHDL -fsyntax-only + style script) integration.
- [ ] CI stub (GitHub Actions or local script) printing timing summary & resource usage.

### Phase 5 – Control & Extensibility

- [ ] Simple register block (pattern select, mode select, audio enable) via lightweight bus.
- [ ] Runtime status: current pattern, frame counter, FIFO level, lock status.
- [ ] Plug-in pattern architecture (procedure callbacks or module interface + mux).
- [ ] Optional overlay / OSD channel (alpha blended test string rendering).

### Phase 6 – Performance & Quality

- [ ] Enable `PIPELINE_BALANCE` automatically for higher pixel clocks.
- [ ] Add second pipeline point in DC-balance stage if > 100 MHz pixel.
- [ ] Support 10-bit and 12-bit deep color (extend encoder to 12-bit path or convert down with dithering).
- [ ] Spread-spectrum PLL option (if device supports) for EMI mitigation.
- [ ] Power gating: disable audio subsystem when not in use (clock enable).

### Phase 7 – Advanced / Optional

- [ ] EDID reader over DDC (I²C) with fallback table.
- [ ] Dynamic resolution negotiation based on EDID.
- [ ] AVI InfoFrame population from mode table.
- [ ] Proper audio channel status bits / sample word length reporting.
- [ ] HDCP intentionally excluded (licensing complexity) – document rationale.
- [ ] TMDS clock recovery margin reporting (optional debug instrumentation).

---
 
## 5. Technical Debt & Cleanup Tasks

| Item | Impact | Priority |
|------|--------|----------|
| Combined vertical-only audio scheduling | Limits sample throughput | High (Phase 2) |
| Hard-coded magic numbers in packetizer | Maintainability | Medium |
| Lack of simulation collateral | Hidden regressions | High |
| Single reset strategy (could refine per-domain) | Minor | Low |
| Broad false-path on HDMI outputs | Masks accidental long paths | Medium |
| Missing output delay constraints | Timing report clarity | Medium |
| No InfoFrame checksums | HDMI spec compliance | Medium |

---
 
## 6. Proposed Generics (Future)

| Generic | Purpose | Example |
|---------|---------|---------|
| `PIXEL_CLOCK_MODE` | Frequency selection strategy | DERIVED_25_200 / EXACT_25_175 |
| `VIDEO_MODE` | Selects timing record | MODE_640x480 |
| `ENABLE_AUDIO` | Gate audio path | true/false |
| `AUDIO_FIFO_DEPTH` | Buffer sizing | 64 |
| `PIPELINE_BALANCE` | TMDS encoder pipelining | true/false |
| `PATTERN_AUTO_CYCLE` | Enable cycling logic | true |
| `NUM_AUDIO_PACKETS` | Frame packet target | 48 / 800 |

---
 
## 7. Risks & Mitigation

| Risk | Description | Mitigation |
|------|-------------|------------|
| Monitor rejects 25.200 MHz variant | Some strict sinks expect 25.175 MHz | Add selectable PLL profile |
| Audio underruns at higher modes | Insufficient FIFO or scheduling | Dynamic pacing + deeper FIFO |
| TMDS timing fails at > 74 MHz | Logic depth in encoder | Enable/add pipelines |
| Resource growth w/ multi-mode | Limited LUT/BRAM on GW1NR-9 | Conditional generates + pruning |
| Complexity creep | Roadmap expansion delays core quality | Phase gating; freeze scope per release |

---
 
## 8. Release Tagging Plan

| Version | Scope |
|---------|-------|
| v0.2.0 | Current multi-packet audio + pipeline generic (baseline) |
| v0.3.0 | Continuous audio (800 samples/frame) + selectable pixel clock |
| v0.4.0 | Multi-mode timing + improved ACR table |
| v0.5.0 | Simulation + CI + InfoFrames (basic) |
| v0.6.0 | Bus control + runtime status block |
| v0.7.0 | Higher resolutions (720p) + encoder auto-pipeline |
| v0.8.0 | Deep color / extended audio options |
| v1.0.0 | EDID + finalized API + documentation polish |

---
 
## 9. Contribution Guidelines (Draft)

1. Keep additions parametric where possible (prefer generics over hard-coded constants).
2. Provide a minimal testbench snippet for new modules.
3. Maintain one feature per commit; multiple commits per PR allowed.
4. Document new generics and timing changes in README & ROADMAP.
5. Avoid vendor-specific primitives unless wrapped in an abstraction layer.

---
 
## 10. Immediate Next Steps (Actionable)

- Add generic for selecting exact vs derived pixel clock.
- Implement ACR cadence refinement + verification counter.
- Introduce simulation testbench skeleton (focus: timing + packet sequencing).
- Replace vertical-only audio scheduling with combined horizontal+vertical strategy or higher density inside vblank.

---
 
## 11. Long-Term Ideas (Parking Lot)

- Lightweight on-screen debug overlay (resolution-independent HUD).
- LUT-based sine audio + multi-tone mixer.
- Scripted coefficient generation for alternative PLL frequencies.
- Portable TMDS encoder extraction into separate IP repo.
- Formal cover points for packet ordering.

---
 
## 12. Appendix: Reference Numbers

| Parameter | Value | Notes |
|-----------|-------|-------|
| Samples / frame (48 kHz @ 60 Hz) | 800 | Target for full audio continuity |
| Current packets / frame (demo) | ~48 (configurable) | Increase toward 800 |
| TMDS serialization factor | 10:1 | Standard HDMI channel format |
| Target future pixel modes | 25–148.5 MHz | Up to 720p/1080p (stretch goal) |

---
*Last updated: (insert date when editing next)*
