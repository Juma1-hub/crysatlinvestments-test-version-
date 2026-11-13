"use client";
import {useEffect,useState} from "react";
import {getSupabaseBrowserClient} from "@/lib/supabase";

type FinancialRequest={
 id:string;investor_id:string;investor_name:string;investor_email:string;investor_phone:string;investor_country:string;
 amount:number;currency:string;status:string;created_at:string;reviewed_at:string|null;reviewed_by_name:string;
 payment_method:string;payment_reference:string;sender_name:string;destination_details:Record<string,unknown>;
};

function detailText(value:unknown){
 if(value===null||value===undefined||value==="")return "—";
 if(typeof value==="object")return Object.entries(value as Record<string,unknown>).filter(([,v])=>v!==null&&v!==undefined&&v!=="").map(([k,v])=>`${k.replaceAll("_"," ")}: ${String(v)}`).join(" · ")||"—";
 return String(value);
}

export default function AdminFinancialRequests({kind}:{kind:"deposit"|"withdrawal"}){
 const [rows,setRows]=useState<FinancialRequest[]>([]),[message,setMessage]=useState(""),[busy,setBusy]=useState<string|null>(null);
 async function load(){
  const db=getSupabaseBrowserClient();if(!db)return;
  const {data,error}=await db.rpc("admin_list_financial_requests",{p_request_type:kind});
  if(error){setMessage("Unable to load requests. Check your assigned access.");return;}
  setRows((data||[]) as FinancialRequest[]);
 }
 useEffect(()=>{void load()},[kind]);
 async function review(id:string,status:"approved"|"rejected"){
  const db=getSupabaseBrowserClient();if(!db)return;
  if(!window.confirm(`${status==="approved"?"Approve":"Reject"} this ${kind} request?`))return;
  setBusy(id);setMessage("");
  const {error}=await db.rpc("admin_review_financial_request",{p_request_type:kind,p_request_id:id,p_status:status});
  setBusy(null);
  if(error){setMessage(error.message);return;}
  setMessage(status==="approved"?(kind==="deposit"?"Deposit approved and automatically allocated across the eight investment divisions.":"Withdrawal approved and posted against the investor's account."):`Request ${status}.`);
  await load();
 }
 return <section className="admin-panel">
  <div className="admin-panel-head"><div><h3>{kind==="deposit"?"Deposit requests":"Withdrawal approval requests"}</h3><p>{kind==="deposit"?"Review verified investor deposits.":"Review the investor, amount, currency and complete payment destination before approval."}</p></div></div>
  {message&&<p className="admin-help" role="status">{message}</p>}
  {rows.length===0?<div className="admin-empty">No requests to display.</div>:<div className="admin-table-wrap"><table className="admin-table">
   <thead><tr><th>Investor</th><th>Amount</th><th>{kind==="deposit"?"Deposit details":"Withdrawal destination details"}</th><th>Status</th><th>Submitted</th><th>Reviewed by</th><th>Actions</th></tr></thead>
   <tbody>{rows.map(r=><tr key={r.id}>
    <td><b>{r.investor_name||"Investor"}</b><small>{r.investor_email}</small><small>{[r.investor_phone,r.investor_country].filter(Boolean).join(" · ")}</small></td>
    <td><b>{r.currency} {Number(r.amount).toLocaleString(undefined,{minimumFractionDigits:2,maximumFractionDigits:2})}</b></td>
    <td><small>{kind==="deposit"?[
      r.payment_method&&`Method: ${r.payment_method}`,r.sender_name&&`Sender: ${r.sender_name}`,r.payment_reference&&`Reference: ${r.payment_reference}`
     ].filter(Boolean).join(" · "):detailText(r.destination_details)}</small></td>
    <td>{r.status}</td><td>{new Date(r.created_at).toLocaleString()}</td><td>{r.reviewed_by_name||"—"}{r.reviewed_at&&<small>{new Date(r.reviewed_at).toLocaleString()}</small>}</td>
    <td className="admin-row-actions">{["pending","submitted","under review","under_review","processing"].includes(String(r.status).toLowerCase())&&<><button disabled={busy===r.id} onClick={()=>void review(r.id,"approved")}>{busy===r.id?"Saving…":"Approve"}</button><button disabled={busy===r.id} onClick={()=>void review(r.id,"rejected")}>Reject</button></>}</td>
   </tr>)}</tbody>
  </table></div>}
 </section>;
}
