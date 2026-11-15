"use client";
import { useCallback, useEffect, useState } from "react";
import { CheckCircle2, RefreshCw, XCircle } from "lucide-react";
import { getSupabaseBrowserClient } from "@/lib/supabase";

type RequestRow = {
  id: string; investor_id: string; amount: number; currency: string; status: string;
  created_at: string; reviewed_at: string | null; reviewed_by: string | null;
  payment_method?: string | null; payment_reference?: string | null; sender_name?: string | null;
  destination_details?: Record<string, unknown> | null;
};

export default function AdminFinancialRequests({ kind }: { kind: "deposit" | "withdrawal" }) {
  const [rows, setRows] = useState<RequestRow[]>([]);
  const [message, setMessage] = useState("");
  const [busyId, setBusyId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const load = useCallback(async () => {
    const db = getSupabaseBrowserClient();
    if (!db) { setMessage("Unable to load requests."); setLoading(false); return; }
    setLoading(true);
    const table = kind === "deposit" ? "deposit_requests" : "withdrawal_requests";
    const { data, error } = await db.from(table).select("*").order("created_at", { ascending: false }).limit(1000);
    if (error) setMessage(error.message);
    else { setRows((data || []) as RequestRow[]); setMessage(""); }
    setLoading(false);
  }, [kind]);
  useEffect(() => { void load(); }, [load]);

  async function review(row: RequestRow, status: "approved" | "rejected") {
    const verb = status === "approved" ? "approve" : "reject";
    const label = kind === "deposit" ? "deposit" : "withdrawal";
    if (!window.confirm(`Are you sure you want to ${verb} this ${label} request for ${row.currency} ${Number(row.amount).toLocaleString()}?`)) return;
    const db = getSupabaseBrowserClient();
    if (!db) { setMessage("Unable to connect to the account service."); return; }
    setBusyId(row.id); setMessage("");
    const { data: assurance, error: assuranceError } = await db.auth.mfa.getAuthenticatorAssuranceLevel();
    if (assuranceError || assurance?.currentLevel !== "aal2") {
      setMessage("Complete multi-factor authentication, then retry this review."); setBusyId(null); return;
    }
    const { error } = await db.rpc("admin_review_financial_request", {
      p_request_type: kind, p_request_id: row.id, p_status: status,
    });
    if (error) setMessage(error.message);
    else setMessage(`${label[0].toUpperCase()}${label.slice(1)} request ${status}.`);
    setBusyId(null);
    await load();
  }

  const pending = rows.filter(r => ["pending", "submitted", "under review", "under_review", "processing"].includes(String(r.status).toLowerCase()));
  const approved = rows.filter(r => String(r.status).toLowerCase() === "approved");
  const rejected = rows.filter(r => ["rejected", "declined", "void"].includes(String(r.status).toLowerCase()));
  const destination = (r: RequestRow) => {
    const d = r.destination_details || {};
    return [d.method, d.bank_name, d.account_holder, d.account_number, d.phone].filter(Boolean).join(" · ") || "—";
  };
  return <section className="admin-panel">
    <div className="admin-panel-head"><div><h3>{kind === "deposit" ? "Deposit approvals" : "Withdrawal approvals"}</h3><p>Review the request details and record an authorised decision.</p></div><button className="admin-secondary" type="button" onClick={() => void load()} disabled={loading || !!busyId}><RefreshCw size={15}/> Refresh</button></div>
    {message && <p className="admin-help" role="status">{message}</p>}
    <div className="admin-stat-grid"><article className="admin-stat"><span>Total requests</span><strong>{rows.length}</strong></article><article className="admin-stat"><span>Awaiting review</span><strong>{pending.length}</strong></article><article className="admin-stat"><span>Approved</span><strong>{approved.length}</strong></article><article className="admin-stat"><span>Rejected / void</span><strong>{rejected.length}</strong></article></div>
    {loading ? <div className="admin-empty">Loading requests…</div> : rows.length === 0 ? <div className="admin-empty">No requests to display.</div> : <div className="admin-table-wrap"><table className="admin-table"><thead><tr><th>Request</th><th>Investor</th><th>Amount</th><th>{kind === "deposit" ? "Payment details" : "Withdrawal destination"}</th><th>Status</th><th>Submitted</th><th>Reviewed</th><th>Decision</th></tr></thead><tbody>{rows.map(row => {
      const isPending = ["pending", "submitted", "under review", "under_review", "processing"].includes(String(row.status).toLowerCase());
      return <tr key={row.id}><td><small>{row.id}</small></td><td><small>{row.investor_id}</small></td><td><b>{row.currency} {Number(row.amount).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</b></td><td>{kind === "deposit" ? <>{row.payment_method || "—"}<small>{row.payment_reference || "No reference"}{row.sender_name ? ` · ${row.sender_name}` : ""}</small></> : destination(row)}</td><td><span className={`admin-pill ${String(row.status || "").toLowerCase().replaceAll(" ", "-")}`}>{row.status}</span></td><td>{row.created_at ? new Date(row.created_at).toLocaleString() : "—"}</td><td>{row.reviewed_at ? new Date(row.reviewed_at).toLocaleString() : "—"}</td><td>{isPending ? <div className="admin-row-actions"><button className="admin-primary" type="button" disabled={!!busyId} onClick={() => void review(row, "approved")}>{busyId === row.id ? "Saving…" : <><CheckCircle2 size={14}/> Approve</>}</button><button className="admin-secondary" type="button" disabled={!!busyId} onClick={() => void review(row, "rejected")}><XCircle size={14}/> Reject</button></div> : "—"}</td></tr>;
    })}</tbody></table></div>}
  </section>;
}
