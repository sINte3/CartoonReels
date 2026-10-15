import type { FC } from "react";

export type Pose = "proud" | "caught" | "working" | "surprised" | "soft" | "deadpan";

type HeroProps = {
  id: string;
  pose?: Pose;
  lookX?: number;
  lookY?: number;
  blink?: number;
  tailTip?: readonly [number, number];
  squash?: number;
};

const ink = "#203e46";

/** Original, layered SVG puppet. Local origin is the point between the feet. */
export const Hero: FC<HeroProps> = ({
  id,
  pose = "proud",
  lookX = 0,
  lookY = 0,
  blink = 0,
  tailTip = [290, -285],
  squash = 0,
}) => {
  const [tx, ty] = tailTip;
  const startled = pose === "surprised";
  const tired = pose === "deadpan";
  const caught = pose === "caught";
  const tail = `M 85 -99 C 236 -23 373 -89 365 -222 C 357 -355 247 -408 204 -333 C 161 -260 ${tx - 95} ${ty + 78} ${tx} ${ty}`;
  const leftHand = startled ? [-162, -235] : caught ? [-158, -143] : pose === "working" ? [-165, -93] : [-112, -81];
  const rightHand = startled ? [158, -231] : caught ? [158, -162] : pose === "working" ? [169, -115] : [113, -80];
  const mouth = startled
    ? "M -9 -166 C -12 -187 14 -191 18 -173 C 22 -153 -6 -149 -9 -166 Z"
    : tired
      ? "M -17 -166 Q 3 -171 23 -166"
      : caught
        ? "M -14 -168 Q 3 -177 22 -165"
        : pose === "soft"
          ? "M -19 -177 Q 3 -154 27 -176"
          : "M -17 -177 Q 1 -156 29 -182";

  return (
    <g>
      <defs>
        <linearGradient id={`${id}-body`} x1="0" y1="0" x2="1" y2="1">
          <stop stopColor="#72b7ad" />
          <stop offset="0.5" stopColor="#499b99" />
          <stop offset="1" stopColor="#2e777e" />
        </linearGradient>
        <linearGradient id={`${id}-tail`} x1="0" y1="0" x2="1" y2="1">
          <stop stopColor="#84657b" />
          <stop offset="0.5" stopColor="#61435f" />
          <stop offset="1" stopColor="#49334f" />
        </linearGradient>
        <linearGradient id={`${id}-cream`} x1="0" y1="0" x2="0" y2="1">
          <stop stopColor="#fff4d9" />
          <stop offset="1" stopColor="#eedabc" />
        </linearGradient>
        <clipPath id={`${id}-left-eye`}><ellipse cx="-39" cy="-242" rx="34" ry="42" /></clipPath>
        <clipPath id={`${id}-right-eye`}><ellipse cx="44" cy="-243" rx="34" ry="42" /></clipPath>
      </defs>

      <ellipse cx="23" cy="8" rx="157" ry="20" fill="#384541" opacity="0.14" />

      {/* Tail root and continuous path stay behind the torso. */}
      <path d={tail} fill="none" stroke="#49334f" strokeWidth="90" strokeLinecap="round" />
      <path d={tail} fill="none" stroke={`url(#${id}-tail)`} strokeWidth="78" strokeLinecap="round" />
      <ellipse cx={tx} cy={ty} rx="40" ry="32" fill="#ed997e" stroke="#49334f" strokeWidth="6" transform={`rotate(-25 ${tx} ${ty})`} />
      <path d={`M ${tx - 19} ${ty - 12} Q ${tx} ${ty - 29} ${tx + 18} ${ty - 10}`} fill="none" stroke="#ffd0a6" strokeWidth="6" strokeLinecap="round" opacity="0.65" />

      <g transform={`scale(${1 + squash} ${1 - squash})`}>
        <ellipse cx="-65" cy="-10" rx="52" ry="26" fill="#327e81" stroke={ink} strokeWidth="5" />
        <ellipse cx="68" cy="-10" rx="52" ry="26" fill="#327e81" stroke={ink} strokeWidth="5" />
        <path d="M -103 -47 C -138 -67 -158 -132 -145 -203 C -139 -247 -121 -271 -102 -296 L -113 -345 C -116 -378 -84 -388 -62 -355 L -45 -334 Q 0 -349 46 -334 L 66 -359 C 90 -387 119 -371 111 -339 L 105 -296 C 138 -255 154 -203 148 -146 C 143 -81 117 -46 70 -35 Q 0 -19 -65 -33 Z" fill={`url(#${id}-body)`} stroke={ink} strokeWidth="5" strokeLinejoin="round" />
        <path d="M -94 -338 Q -102 -361 -86 -358 L -67 -335 Z" fill="#eebda3" opacity="0.8" />
        <path d="M 73 -336 L 91 -357 Q 103 -359 95 -335 Z" fill="#eebda3" opacity="0.8" />
        <path d="M -27 -329 Q -19 -357 0 -363 Q -4 -343 13 -334" fill="#65ada6" stroke={ink} strokeWidth="5" strokeLinecap="round" />
        <ellipse cx="7" cy="-99" rx="68" ry="53" fill="#92c4b3" opacity="0.35" />

        <path d={`M -117 -169 Q -163 -145 ${leftHand[0]} ${leftHand[1]}`} fill="none" stroke={ink} strokeWidth="34" strokeLinecap="round" />
        <path d={`M -117 -169 Q -163 -145 ${leftHand[0]} ${leftHand[1]}`} fill="none" stroke="#519f9c" strokeWidth="25" strokeLinecap="round" />
        <ellipse cx={leftHand[0]} cy={leftHand[1]} rx="24" ry="22" fill="#6bafa7" stroke={ink} strokeWidth="4" />
        <path d={`M 121 -168 Q 163 -151 ${rightHand[0]} ${rightHand[1]}`} fill="none" stroke={ink} strokeWidth="34" strokeLinecap="round" />
        <path d={`M 121 -168 Q 163 -151 ${rightHand[0]} ${rightHand[1]}`} fill="none" stroke="#499a97" strokeWidth="25" strokeLinecap="round" />
        <ellipse cx={rightHand[0]} cy={rightHand[1]} rx="24" ry="22" fill="#6bafa7" stroke={ink} strokeWidth="4" />

        <ellipse cx="5" cy="-180" rx="77" ry="56" fill={`url(#${id}-cream)`} />
        <g transform={`translate(0 -242) scale(1 ${Math.max(0.06, 1 - blink * 0.94)}) translate(0 242)`}>
          <ellipse cx="-39" cy="-242" rx="34" ry={startled ? 47 : 42} fill="#fff9e8" stroke={ink} strokeWidth="4" />
          <ellipse cx="44" cy="-243" rx="34" ry={startled ? 47 : 42} fill="#fff9e8" stroke={ink} strokeWidth="4" />
          <ellipse cx={-34 + lookX * 12} cy={-239 + lookY * 9} rx={startled ? 12 : 15} ry={startled ? 18 : 22} fill={ink} />
          <ellipse cx={47 + lookX * 12} cy={-240 + lookY * 9} rx={startled ? 12 : 15} ry={startled ? 18 : 22} fill={ink} />
          <ellipse cx={-38 + lookX * 12} cy={-247 + lookY * 9} rx="4.5" ry="6" fill="white" />
          <ellipse cx={43 + lookX * 12} cy={-248 + lookY * 9} rx="4.5" ry="6" fill="white" />
          {tired ? <><g clipPath={`url(#${id}-left-eye)`}><path d="M -82 -292 H 4 V -245 Q -38 -257 -82 -255 Z" fill="#4c9e9b" /><path d="M -82 -255 Q -38 -257 4 -245" fill="none" stroke={ink} strokeWidth="4" /></g><g clipPath={`url(#${id}-right-eye)`}><path d="M 2 -292 H 86 V -259 Q 47 -258 2 -248 Z" fill="#4c9e9b" /><path d="M 2 -248 Q 47 -258 86 -259" fill="none" stroke={ink} strokeWidth="4" /></g></> : null}
        </g>
        <path d={startled ? "M -70 -307 Q -45 -323 -18 -307" : caught ? "M -72 -289 Q -41 -308 -16 -298" : "M -69 -296 Q -44 -309 -18 -297"} fill="none" stroke={ink} strokeWidth="9" strokeLinecap="round" />
        <path d={startled ? "M 17 -308 Q 43 -324 72 -310" : caught ? "M 18 -299 L 74 -286" : tired ? "M 17 -294 L 74 -298" : "M 19 -298 Q 45 -311 72 -296"} fill="none" stroke={ink} strokeWidth="9" strokeLinecap="round" />
        <path d="M -13 -210 Q 1 -221 18 -212 Q 13 -195 2 -196 Q -9 -198 -13 -210" fill={ink} />
        <ellipse cx="-5" cy="-212" rx="5" ry="2" fill="#7ba29c" />
        <path d={mouth} fill={startled ? ink : "none"} stroke={ink} strokeWidth="5" strokeLinecap="round" />
        <ellipse cx="-64" cy="-183" rx="14" ry="8" fill="#e9ac94" opacity="0.7" />
        <ellipse cx="70" cy="-184" rx="14" ry="8" fill="#e9ac94" opacity="0.7" />
      </g>
    </g>
  );
};
