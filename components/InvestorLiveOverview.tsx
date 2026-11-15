"use client";
import {useEffect,useState} from "react";
import {getSupabaseBrowserClient} from "@/lib/supabase";
type Balance={currency:string;available_balance:number;invested_capital:number;accumulated_interest:number;total_account_value:number};
const fmt=(n:number,c:string)=>`${c} ${Number(n||0).toLocaleString(undefined,{minimumFractionDigits:2,maximumFractionDigits:2})}`;
export default function InvestorLiveOverview(){
 const [rows,setRows]=useState<Balance[]>([]);const [loaded,setLoaded]=useState(false);
 useEffect(()=>{let live=true;const db=getSupabaseBrowserClient();if(!db){setLoaded(true);return;}void db.rpc("investor_get_account_balances").then(({data,error})=>{if(!live)return;if(!error&&Array.isArray(data))setRows(data as Balance[]);setLoaded(true);});return()=>{live=false};},[]);
 if(!loaded||rows.length===0)return null;
 return <section className="investor-grid" aria-label="Investor account values">{rows.map(row=><article className="portal-card income-panel" key={row.currency}><div className="card-heading"><div><span className="eyebrow">{row.currency} ACCOUNT</span><h3>{fmt(row.total_account_value,row.currency)}</h3></div></div><div className="admin-metric-row"><span>Available balance</span><b>{fmt(row.available_balance,row.currency)}</b></div><div className="admin-metric-row"><span>Invested capital</span><b>{fmt(row.invested_capital,row.currency)}</b></div><div className="admin-metric-row"><span>Accumulated earnings</span><b>{fmt(row.accumulated_interest,row.currency)}</b></div></article>)}</section>;
}
