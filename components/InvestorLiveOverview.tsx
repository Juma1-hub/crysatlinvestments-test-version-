"use client";
import { ShieldCheck } from "lucide-react";
export default function InvestorLiveOverview() {
  return <section className="investor-grid" aria-label="Investor account values">
    <article className="portal-card income-panel" style={{ gridColumn: "1 / -1" }}>
      <div className="card-heading"><div><span className="eyebrow">ACCOUNT VALUES</span><h3>Financial reconciliation in progress</h3></div><ShieldCheck size={20}/></div>
      <p>Account balances and earnings will be displayed once the existing deposit, allocation and ledger records have been reconciled and verified. No estimated or unreconciled balance is shown here.</p>
    </article>
  </section>;
}
