// Re:Box demo data — accounts, threads, AI briefs.
window.RB_ACCOUNTS = [
  { id: "g1", label: "work · gmail",    email: "alex@studio.eu",    color: "var(--cobalt-400)" },
  { id: "m1", label: "work · m365",     email: "a.chen@partners.io",color: "var(--violet-400)" },
  { id: "g2", label: "personal",        email: "alex@me.eu",        color: "var(--citron-500)" }
];

window.RB_FOLDERS = [
  { id: "inbox",   name: "Inbox",        count: 12, icon: "inbox" },
  { id: "reply",   name: "Needs reply",  count: 4,  icon: "reply" },
  { id: "due",     name: "Has deadline", count: 3,  icon: "clock" },
  { id: "att",     name: "Attachments",  count: 9,  icon: "paperclip" },
  { id: "logged",  name: "Logged",       count: 7,  icon: "check" },
  { id: "starred", name: "Starred",      count: 2,  icon: "star" },
  { id: "sent",    name: "Sent",         count: null,icon: "send" },
  { id: "arch",    name: "Archive",      count: null,icon: "archive" }
];

window.RB_THREADS = [
  {
    id: "t1", account: "g1", from: "Marta Kowalski", fromHandle: "MK",
    fromColor: "linear-gradient(135deg,var(--cobalt-500),var(--violet-500))",
    subject: "Contract approval — Acme GmbH", time: "11:42", unread: true,
    preview: "Client approved pricing and asks for the contract draft by Friday…",
    chips: [{ kind: "due", label: "Fri EOD", urgent: true, hoursLeft: 52 }, { kind: "att", pages: 7 }],
    brief: {
      summary: "Client approved pricing and asks for the contract draft by Friday.",
      request: "Send contract draft",
      deadline: "Fri · May 15",
      risk: "Tight turnaround",
      nextStep: "Draft reply with contract attached",
      confidence: 0.88,
      evidence: ["msg_1", "msg_3", "contract.pdf p.2"]
    },
    messages: [
      { from: "Marta Kowalski", time: "Mon 09:12", body: "Hi Alex — we reviewed the proposal. Pricing works. Can you send the contract draft by Friday so we can sign next week?" },
      { from: "Alex (you)", time: "Mon 14:40", body: "Marta, glad we're aligned. I'll have a draft over before end of week." },
      { from: "Marta Kowalski", time: "Tue 11:42", body: "Quick nudge — Friday EOD would be ideal, otherwise we miss the legal window. Attaching the last revision of the contract for reference." }
    ],
    attachment: { name: "contract.pdf", pages: 7, size: "284 KB" }
  },
  {
    id: "t2", account: "m1", from: "Jonas R.", fromHandle: "JR",
    fromColor: "linear-gradient(135deg,#9a9c99,#56585a)",
    subject: "Re: SaaS renewal — Q3", time: "10:08", unread: true,
    preview: "Adding the legal team. Can you confirm the seat count by Wednesday?",
    chips: [{ kind: "reply", label: "Wed" }, { kind: "cc", label: "+ legal" }],
    brief: {
      summary: "Jonas wants seat count for Q3 renewal confirmed by Wednesday.",
      request: "Confirm seat count",
      deadline: "Wed · May 14",
      risk: "Legal team CC'd",
      nextStep: "Reply with current seat count",
      confidence: 0.92,
      evidence: ["msg_2"]
    },
    messages: [
      { from: "Jonas R.", time: "Yesterday 16:30", body: "Hey — kicking off Q3 renewal. Adding our legal team. Can you confirm the seat count by Wednesday?" }
    ]
  },
  {
    id: "t3", account: "g2", from: "Cveta Vlahova", fromHandle: "CV",
    fromColor: "linear-gradient(135deg,var(--citron-500),var(--citron-700))",
    fromTextColor: "var(--graphite-950)",
    subject: "Lease addendum", time: "Yest.", unread: false,
    preview: "Attached. Let me know if 12 months is fine.",
    chips: [{ kind: "att", pages: 3 }],
    brief: null,
    attachment: { name: "lease_addendum.pdf", pages: 3, size: "112 KB" }
  },
  {
    id: "t4", account: "g1", from: "Sven Christensen", fromHandle: "SC",
    fromColor: "linear-gradient(135deg,#56585a,#2a2c2e)",
    subject: "Re: pricing thread", time: "Mon", unread: false,
    preview: "Logged to HubSpot · 2 action items extracted",
    chips: [{ kind: "logged", target: "HubSpot" }, { kind: "ai", label: "2 actions" }]
  },
  {
    id: "t5", account: "m1", from: "Lena Park", fromHandle: "LP",
    fromColor: "linear-gradient(135deg,var(--violet-500),var(--cobalt-600))",
    subject: "Design review — Tue 4pm", time: "Mon", unread: false,
    preview: "Calendar invite + Figma link inside. Bring Q3 mocks.",
    chips: [{ kind: "cal", label: "Tue 4pm" }]
  },
  {
    id: "t6", account: "g1", from: "Recruiting · Notion", fromHandle: "NO",
    fromColor: "linear-gradient(135deg,#fff,#ccc)", fromTextColor: "#0e1014",
    subject: "Weekly digest — 4 candidates", time: "Sun", unread: false,
    preview: "Filtered by your rules. 2 strong, 1 maybe, 1 archived.",
    chips: [{ kind: "ai", label: "digest" }]
  },
  {
    id: "t7", account: "g2", from: "Stripe", fromHandle: "ST",
    fromColor: "linear-gradient(135deg,#635bff,#3a31c0)",
    subject: "Invoice #INV-2418", time: "Sat", unread: false,
    preview: "Paid · €1,840 · receipt attached", chips: [{ kind: "paid", label: "€1,840" }, { kind: "att", pages: 1 }]
  }
];
