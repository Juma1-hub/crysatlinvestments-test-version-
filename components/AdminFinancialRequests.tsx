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
  return <section className="admin-panel"><div className="admin-panel-head"><div><h3>{kind === "deposit" ? "Deposit requests" : "Withdrawal requests"}</h3><p>Requests are displayed from Supabase. Approval actions are locked until the live financial ledger has been reconciled and the required automatic allocation / proportional withdrawal controls are installed.</p></div><button className="admin-secondary" type="button" onClick={() => void load()}>Refresh</button></div>
    <div className="admin-help" role="status">Financial approval is temporarily fail-closed. Do not approve or reject existing requests until the outstanding deposit-to-ledger discrepancies and pending withdrawal reservations have been reviewed.</div>
    {rows.length === 0 ? <div className="admin-empty">No requests to display.</div> : <div className="admin-table-wrap"><table className="admin-table"><thead><tr><th>Investor</th><th>Amount</th><th>Payment / destination details</th><th>Status</th><th>Received</th></tr></thead><tbody>{rows.map(row => <tr key={row.id}><td>{row.investor_id}</td><td>{row.currency} {Number(row.amount).toLocaleString()}</td><td>{kind === "deposit" ? `${row.payment_method || ""} · ${row.sender_name || ""} · ${row.payment_reference || ""}` : JSON.stringify(row.destination_details || {})}</td><td>{row.status}</td><td>{new Date(row.created_at).toLocaleString()}</td></tr>)}</tbody></table></div>}
  </section>;
}
