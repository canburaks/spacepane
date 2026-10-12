import React from 'react';
import {interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {color, ease, font, layout, springs} from '../theme/tokens';

// "Plain text with *serif italic* accents" -> words with an accent flag.
type Segment = {text: string; accent: boolean};
const parse = (text: string): Segment[][] => {
  const words: Segment[][] = [];
  let previousEndsWithSpace = true;
  text.split('*').forEach((chunk, i) => {
    const accent = i % 2 === 1;
    let joinPrevious = !previousEndsWithSpace && !/^\s/.test(chunk) && words.length > 0;
    for (const token of chunk.split(/(\s+)/)) {
      if (token === '') continue;
      if (/^\s+$/.test(token)) {
        joinPrevious = false;
        continue;
      }
      if (joinPrevious) words[words.length - 1].push({text: token, accent});
      else words.push([{text: token, accent}]);
      joinPrevious = false;
    }
    if (chunk.length > 0) previousEndsWithSpace = /\s$/.test(chunk);
  });
  return words;
};

export const Headline: React.FC<{
  text: string;
  size?: number;
  start: number;
  end: number;
  stagger?: number;
}> = ({text, size = 80, start, end, stagger = 2}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const words = parse(text);
  const out = interpolate(frame, [end, end + 8], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease.inOut});
  return (
    <div
      style={{
        fontFamily: font.display,
        fontWeight: 600,
        fontSize: size,
        lineHeight: 1.06,
        letterSpacing: '-0.035em',
        color: color.white,
        textAlign: 'center',
        textShadow: '0 4px 36px rgba(24,6,80,0.38)',
        opacity: 1 - out,
        transform: `translate3d(0, ${-out * 18}px, 0)`,
        whiteSpace: 'nowrap',
      }}
    >
      {words.map((w, i) => {
        const p = spring({frame: frame - start - i * stagger, fps, config: springs.ui});
        const o = interpolate(p, [0, 0.45], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
        return (
          <span
            key={i}
            style={{
              display: 'inline-block',
              marginRight: i === words.length - 1 ? 0 : '0.25em',
              opacity: o,
              transform: `translate3d(0, ${(1 - p) * 36}px, 0)`,
              filter: p < 0.98 ? `blur(${(1 - p) * 9}px)` : undefined,
            }}
          >
            {w.map((seg, j) =>
              seg.accent ? (
                <span key={j} style={{fontFamily: font.serif, fontStyle: 'italic', fontWeight: 500, letterSpacing: '-0.02em', fontSize: '1.04em'}}>
                  {seg.text}
                </span>
              ) : (
                <React.Fragment key={j}>{seg.text}</React.Fragment>
              ),
            )}
          </span>
        );
      })}
    </div>
  );
};

export const Eyebrow: React.FC<{text: string; start: number; end: number}> = ({text, start, end}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const p = spring({frame: frame - start, fps, config: springs.ui});
  const out = interpolate(frame, [end, end + 8], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease.inOut});
  return (
    <div
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        height: 44,
        padding: '0 24px',
        borderRadius: 22,
        background: 'rgba(255,255,255,0.20)',
        color: color.white,
        fontFamily: font.text,
        fontWeight: 600,
        fontSize: 21,
        letterSpacing: '0.16em',
        textTransform: 'uppercase',
        opacity: Math.min(1, p * 1.6) * (1 - out),
        transform: `translate3d(0, ${(1 - p) * 14 - out * 10}px, 0)`,
      }}
    >
      {text}
    </div>
  );
};

/** Eyebrow + one-line headline (+ optional note) centred at the top of the frame. */
export const Header: React.FC<{
  eyebrow?: string;
  headline: string;
  note?: string;
  start?: number;
  end: number;
}> = ({eyebrow, headline, note, start = 6, end}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const noteP = spring({frame: frame - start - 16, fps, config: springs.ui});
  const noteOut = interpolate(frame, [end, end + 8], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return (
    <div style={{position: 'absolute', left: 0, right: 0, top: layout.headerTop, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 20}}>
      {eyebrow ? <Eyebrow text={eyebrow} start={start} end={end} /> : null}
      <Headline text={headline} start={start + 2} end={end} />
      {note ? (
        <div
          style={{
            marginTop: -2,
            fontFamily: font.text,
            fontWeight: 500,
            fontSize: 34,
            letterSpacing: '-0.01em',
            color: 'rgba(255,255,255,0.92)',
            opacity: Math.min(1, noteP * 1.5) * (1 - noteOut),
            transform: `translate3d(0, ${(1 - noteP) * 14}px, 0)`,
          }}
        >
          {note}
        </div>
      ) : null}
    </div>
  );
};
