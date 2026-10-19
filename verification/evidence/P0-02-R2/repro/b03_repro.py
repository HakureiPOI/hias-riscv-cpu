import importlib.util, json
spec=importlib.util.spec_from_file_location('old','/tmp/opencode/r2/repro/old/check_retire_contract.py')
old=importlib.util.module_from_spec(spec); spec.loader.exec_module(old)
# Hidden CSR: CSRRS x0, mstatus, x0 encoded 0x30002073, but csr_valid=false
rec={"schema":"hias-retire/2","kind":"normal","source":"synthetic","seq":1,
     "token":{"idx":1,"gen":0},"token_valid":True,
     "pc":0x80000000,"instr":0x30002073,"next_pc":0x80000004,"next_pc_valid":True,
     "priv":"M","rd_we":False,"rd":0,"rd_data":None,
     "csr_valid":False,"csr_rd_valid":False,"csr_wr_valid":False,
     "csr_addr":None,"csr_wdata":None,"csr_rdata":None,
     "mem_valid":False,"mem_we":False,"mem_va":None,"mem_pa":None,
     "mem_size":"none","mem_mask":None,"mem_wdata":None,"mem_rdata":None,
     "derived_fields":[],"not_observed_fields":[]}
try:
    old.validate_normal(rec); print("B03_hidden_csr_accepted=1")
except Exception as e:
    print("B03_hidden_csr_accepted=0 reason=",e)
# Duplicate non-empty bundle with repeated first seq
def n(seq):
    r=dict(rec); r.update({"seq":seq,"instr":0x00100093,"csr_valid":False,
        "csr_rd_valid":False,"csr_wr_valid":False,"rd_we":True,"rd":1,"rd_data":1})
    return r
b1={"schema":"hias-retire/2","kind":"bundle","seq_base":1,"slots":[n(1)],"trap":None}
b2={"schema":"hias-retire/2","kind":"bundle","seq_base":1,"slots":[n(1)],"trap":None}
try:
    old.validate_stream([b1,b2]); print("B03_duplicate_bundle_accepted=1")
except Exception as e:
    print("B03_duplicate_bundle_accepted=0 reason=",e)
# token_valid wrong type
r=dict(rec); r["token_valid"]=1; r["token"]={"idx":1,"gen":0}
try:
    old.validate_normal(r); print("B03_token_valid_int_accepted=1")
except Exception as e:
    print("B03_token_valid_int_accepted=0 reason=",e)
