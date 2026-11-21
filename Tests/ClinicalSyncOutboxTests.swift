import Foundation
@main enum Tests {
 static func main() throws {
  let directory=FileManager.default.temporaryDirectory.appendingPathComponent("clinical-outbox-"+UUID().uuidString)
  defer { try? FileManager.default.removeItem(at:directory) }
  let account=UUID(); let other=UUID()
  func sample(_ value:String,record:String?=nil)->ClinicalDisplayValue {
   ClinicalDisplayValue(event_id:UUID(),key:"future-metric",display_kind:record == nil ? "current":"history",title:"Future metric",section:"Synthetic",value:value,unit:"unit",source:"Synthetic",measured_at:record == nil ? nil:"2000-01-01T00:00:00Z",observed_at:"2026-11-21T00:00:00Z",record_id:record)
  }
  let outbox=try ClinicalSyncOutbox(accountID:account,directory:directory)
  let first=sample("A");try outbox.enqueue([first]);try outbox.enqueue([sample("A")])
  precondition(outbox.pendingCount==1,"unchanged readings must not duplicate")
  let second=sample("B");let again=sample("A")
  try outbox.enqueue([second,again]);precondition(outbox.pendingCount==3,"A-B-A changes must all survive")
  let recovered=try ClinicalSyncOutbox(accountID:account,directory:directory)
  precondition(recovered.page().map(\.event_id)==[first,second,again].map(\.event_id),"failed uploads must retry exact event IDs")
  try recovered.acknowledge([first]);precondition(recovered.pendingCount==2,"only acknowledged events are removed")
  let isolated=try ClinicalSyncOutbox(accountID:other,directory:directory);precondition(isolated.pendingCount==0,"account isolation")
  let a=sample("same",record:"source-a");let b=sample("same",record:"source-b")
  try recovered.enqueue([a,b]);let total=recovered.pendingCount;try recovered.enqueue([a,b]);precondition(recovered.pendingCount==total,"same-time source histories stay distinct without endless duplicates")
  try Data("corrupt".utf8).write(to:directory.appendingPathComponent(other.uuidString+".json"))
  do { _=try ClinicalSyncOutbox(accountID:other,directory:directory);fatalError("corruption silently discarded") } catch {}
  print("Outbox tests passed: exact retries, restarts, acknowledgements, deduplication, recurrent values, source histories and account isolation.")
 }
}
