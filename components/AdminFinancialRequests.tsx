"use client";
import { useEffect, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase";
export default function AdminFinancialRequests({ kind }: { kind: "deposit" | "withdrawal" }) {
  const [rows, setRows] = useState<any[]>([]);
  const [message, setMessage] = useState("");
  async function load() {
    const db = getSupabaseBrowserClient(); if (!db) { setMessage("Supabase is not configured."); return; }
    const table = kind === "deposit" ? "deposit_requests" : "withdrawal_requests";
    const { data, error } = await db.from(table).select("*").order("created_at", { ascending: false });
    if (error) { setMessage(`Requests could not be loaded: ${error.message}`); return; }
    setRows(data || []);
  }
  useEffect(() => { void load(); }, [kind]);
  const pendingCount = rows.filter(row => String(row.status).toLowerCase() === "pending").length;
  const approvedCount = rows.filter(row => String(row.status).toLowerCase() === "approved").length;
  const rejectedCount = rows.filter(row => ["rejected","declined","void"].includes(String(row.status).toLowerCase())).length;
  return <section className="admin-panel"><div className="admin-panel-head"><div><h3>{kind === "deposit" ? "Deposit requests" : "Withdrawal requests"}</h3><p>Review each request, its investor reference, payment or destination details, status and review timestamps.</p></div><button className="admin-secondary" type="button" onClick={() => void load()}>Refresh</button></div>
    {message && <p className="admin-help" role="alert">{message}</p>}
    <div className="admin-stat-grid"><article className="admin-stat"><span>Total requests</span><strong>{rows.length}</strong></article><article className="admin-stat"><span>Pending</span><strong>{pendingCount}</strong></article><article className="admin-stat"><span>Approved</span><strong>{approvedCount}</strong></article><article className="admin-stat"><span>Rejected / void</span><strong>{rejectedCount}</strong></article></div>
    {rows.length === 0 ? <div className="admin-empty">No requests to display.</div> : <div className="admin-table-wrap"><table className="admin-table"><thead><tr><th>Request ID</th><th>Investor ID</th><th>Amount</th><th>Method / destination</th><th>Reference / sender</th><th>Status</th><th>Received</th><th>Reviewed</th></tr></thead><tbody>{rows.map(row => <tr key={row.id}><td><small>{String(row.id).slice(0, 8)}</small></td><td><small>{row.investor_id}</small></td><td><b>{row.currency} {Number(row.amount).toLocaleString(undefined,{minimumFractionDigits:2,maximumFractionDigits:2})}</b></td><td>{kind === "deposit" ? (row.payment_method || "—") : JSON.stringify(row.destination_details || {})}</td><td>{kind === "deposit" ? `${row.payment_reference || "—"}${row.sender_name ? ` · ${row.sender_name}` : ""}` : (row.destination_details?.account_name || row.destination_details?.phone || "—")}</td><td><span className={`admin-pill ${String(row.status||"").toLowerCase()}`}>{row.status}</span></td><td>{row.created_at ? new Date(row.created_at).toLocaleString() : "—"}</td><td>{row.reviewed_at ? new Date(row.reviewed_at).toLocaleString() : "—"}</td></tr>)}</tbody></table></div>}
  </section>;
}
