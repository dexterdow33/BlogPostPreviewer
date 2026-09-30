# NH dynamicdatadump discovery report

Generated 2026-09-30T03:44:45+00:00 (offline rebuild from data/raw)

_Offline rebuild: files read from data/raw._

## LSRs.txt

one row per legislative service request / bill in the current session

- bytes: 435,828; rows: 1,387; sha256: fac11ebc896b8548
- field-count histogram: 39: 1387


```
[0]=2026
[1]=0001
[2]=relative to the transfer of state-owned real property to municipalities.
[3]=H
[4]=1
[5]=0
[6]=0
[7]=0
[8]=25-0001
[9]=HB  0561
[10]=HB561
[11]=
[12]=MUN
[13]=H20
[14]=H20
[15]=1/9/2025 12:00:00 AM
[16]=07
[17]=
[18]=3/20/2025 12:00:00 AM
[19]=1/7/2026 12:00:00 AM
[20]=0
[21]=
[22]=
[23]=
[24]=
[25]=
[26]=
[27]=
[28]=0
[29]=02
[30]=H20
[31]=2/4/2025 10:00:00 AM
[32]=LOB Room 201
[33]=
[34]=
[35]=
[36]=0
[37]=0
[38]=
```

```
[0]=2026
[1]=0010
[2]=allowing alternative treatment centers to operate for-profit.
[3]=H
[4]=1
[5]=0
[6]=1
[7]=0
[8]=25-0010
[9]=HB  0054
[10]=HB54
[11]=
[12]=PMH
[13]=H09
[14]=H34
[15]=1/8/2025 12:00:00 AM
[16]=10
[17]=
[18]=3/6/2025 12:00:00 AM
[19]=1/7/2026 12:00:00 AM
[20]=0
[21]=S10
[22]=S10
[23]=1/29/2026 12:00:00 AM
[24]=06
[25]=04/09/2026
[26]=
[27]=4/9/2026 12:00:00 AM
[28]=0
[29]=03
[30]=S10
[31]=2/17/2026 1:40:00 PM
[32]=SH Room 100
[33]=
[34]=
[35]=
[36]=0
[37]=0
[38]=
```

## LsrsOnly.txt

sponsor rows with bill-page document id and title

- bytes: 1,010,937; rows: 7,039; sha256: 3cb6cd7c3a33b4a6
- field-count histogram: 8: 6963, 1: 76


```
[0]=26-2001
[1]=944
[2]=1190
[3]=2026
[4]=Sponsor
[5]=SB416
[6]=H
[7]=relative to the pooling and sharing of tips among tipped employees.
```

```
[0]=26-2001
[1]=8747
[2]=1190
[3]=2026
[4]=Sponsor
[5]=SB416
[6]=S
[7]=relative to the pooling and sharing of tips among tipped employees.
```

## Docket.txt

docket actions (one row per action)

- bytes: 3,200,171; rows: 25,352; sha256: d15ecb40c6bec852
- field-count histogram: 7: 25352


```
[0]=2025
[1]=0173
[2]=12/4/2024 10:44:26 AM
[3]=SR1
[4]=S
[5]=Introduced and Adopted, VV; 12/04/2024;  SJ 1
[6]=12/4/2024 10:44:26 AM
```

```
[0]=2025
[1]=0174
[2]=12/4/2024 10:44:54 AM
[3]=SR2
[4]=S
[5]=Introduced and Adopted, VV; 12/04/2024;  SJ 1
[6]=12/4/2024 10:44:54 AM
```

## LsrSponsors.txt

sponsors in sequence, with prime flag

- bytes: 165,340; rows: 8,571; sha256: e9d228409d6c9487
- field-count histogram: 5: 8571


```
[0]=2026
[1]=2111
[2]=3
[3]=35
[4]=0
```

```
[0]=2026
[1]=2051
[2]=4
[3]=35
[4]=0
```

## legislators.txt

legislator roster

- bytes: 42,959; rows: 406; sha256: 4e60e5be8c425e91
- field-count histogram: 15: 406


```
[0]=11332
[1]=Mannion
[2]=Tim
[3]=E
[4]=H
[5]=3084
[6]=6
[7]=1
[8]=R
[9]=State House-House Member Mail
[10]=107 North Main Street
[11]=Concord
[12]=NH
[13]=03301
[14]=Tim.Mannion@gc.nh.gov
```

```
[0]=11461
[1]=Reardon
[2]=Tara
[3]=
[4]=S
[5]=
[6]=7
[7]=15
[8]=D
[9]=
[10]=
[11]=
[12]=NH
[13]=
[14]=Tara.Reardon@gc.nh.gov
```

## RollCallSummary.txt

roll-call tallies

- bytes: 68,713; rows: 419; sha256: 6917b2611045f174
- field-count histogram: 15: 419


```
[0]=2026
[1]=H
[2]=1
[3]=1/7/2026 10:15:33 AM
[4]=
[5]=321
[6]=2
[7]=34
[8]=38
[9]=
[10]=
[11]=Call of the Roll
[12]=
[13]=
[14]=
```

```
[0]=2026
[1]=H
[2]=2
[3]=1/7/2026 10:25:50 AM
[4]=
[5]=57
[6]=280
[7]=20
[8]=38
[9]=
[10]=
[11]=Rules Suspension
[12]=
[13]=
[14]=
```

## RollCallHistory.txt

per-legislator roll-call votes

- bytes: 4,843,173; rows: 131,199; sha256: 9aafbda262373e8d
- field-count histogram: 8: 131199


```
[0]=2026
[1]=H
[2]=1
[3]=332247
[4]=960
[5]=
[6]=Not Voting/Excused
[7]=
```

```
[0]=2026
[1]=H
[2]=1
[3]=368423
[4]=411
[5]=
[6]=Yea
[7]=
```

## Committees.txt

committee codes and names

- bytes: 2,466; rows: 55; sha256: dba3b08bf1374fa4
- field-count histogram: 3: 55


```
[0]=H05
[1]=Education
[2]=EDUCATION
```

```
[0]=H06
[1]=Environment and Agriculture
[2]=E&A
```


## Parse: legislators.txt

{"lines": 406, "records": 406, "expected_fields": 15, "joined": 0, "irregular": 0}


## Parse: LSRs.txt

{"lines": 1387, "records": 1387, "expected_fields": 39, "joined": 0, "irregular": 0}

Session years: {'2026': 1387}


## Parse: LsrsOnly.txt

{"lines": 7039, "records": 6963, "expected_fields": 8, "joined": 76, "irregular": 0}


## Parse: Docket.txt

{"lines": 25352, "records": 25352, "expected_fields": 7, "joined": 0, "irregular": 0}

Session years: {'2025': 9812, '2026': 15540}


### Most common docket action patterns

```
   886  Executive Session: <date> <n>:<n> am GP <n>
   682  Enrolled Adopted, VV, (In recess <date>); SJ <n>
   658  Enrolled (in recess of) <date> HJ <n> P. <n>
   632  Public Hearing: <date> <n>:<n> am GP <n>
   578  Inexpedient to Legislate: MA VV <date> HJ <n> P. <n>
   503  Hearing: <date>, Room <n>, SH, <n>:<n> am; SC <n>
   503  Committee Report: Inexpedient to Legislate <date> (Vote <n>-<n>; CC) HC <n> P. <n>
   486  Executive Session: <date> <n>:<n> am LOB <n>-<n>
   461  Committee Amendment <amend>, AA, VV; <date>; SJ <n>
   459  Amendment <amend>: AA VV <date> HJ <n> P. <n>
   423  Public Hearing: <date> <n>:<n> pm GP <n>
   401  Ought to Pass with Amendment<amend>: MA VV <date> HJ <n> P. <n>
   398  Public Hearing: <date> <n>:<n> am LOB <n>-<n>
   384  Committee Report: Ought to Pass, <date>; Vote <n>-<n>; CC; SC <n>
   380  Ought to Pass: MA, VV; OT3rdg; <date>; SJ <n>
   378  Ought to Pass with Amendment <amend>, MA, VV; OT3rdg; <date>; SJ <n>
   366  Committee Report: Ought to Pass with Amendment <amend>, <date>; Vote <n>-<n>; CC; SC <n>
   366  Minority Committee Report: Inexpedient to Legislate
   366  Executive Session: <date> <n>:<n> pm GP <n>
   357  Ought to Pass: MA VV <date> HJ <n> P. <n>
   353  Public Hearing: <date> <n>:<n> pm LOB <n>-<n>
   310  Hearing: <date>, Room <n>, SH, <n>:<n> pm; SC <n>
   257  Executive Session: <date> <n>:<n> pm LOB <n>-<n>
   242  Full Committee Work Session: <date> <n>:<n> am GP <n>
   236  Committee Report: Ought to Pass <date> (Vote <n>-<n>; CC) HC <n> P. <n>
   236  Majority Committee Report: Inexpedient to Legislate <date> (Vote <n>-<n>; RC) HC <n> P. <n>
   214  Minority Committee Report: Ought to Pass
   203  Signed by the Governor on <date>; Chapter <n>; Effective <date>
   202  Introduced <date> and Referred to Judiciary; SJ <n>
   201  Signed by Governor Ayotte <date>; Chapter <n>; eff. <date>
   180  Committee Report: Ought to Pass with Amendment <amend> <date> (Vote <n>-<n>; CC) HC <n> P. <n>
   175  Introduced <date> and Referred to Executive Departments and Administration; SJ <n>
   166  Hearing: <date>, Room <n>, LOB, <n>:<n> am; SC <n>
   164  Retained in Committee
   152  Introduced <date> and Referred to Election Law and Municipal Affairs; SJ <n>
   141  Introduced <date> and Referred to Health and Human Services; SJ <n>
   141  Majority Committee Report: Ought to Pass with Amendment <amend> <date> (Vote <n>-<n>; RC) HC <n> P. <n>
   139  Inexpedient to Legislate, MA, VV === BILL KILLED ===; <date>; SJ <n>
   137  Committee Report: Ought to Pass, <date>, Vote <n>-<n>; SC <n>
   136  Committee Report: Ought to Pass with Amendment <amend>, <date>, Vote <n>-<n>; SC <n>
   136  Majority Committee Report: Ought to Pass <date> (Vote <n>-<n>; RC) HC <n> P. <n>
   136  Subcommittee Work Session: <date> <n>:<n> am GP <n>
   134  Introduced <date> and Referred to Commerce; SJ <n>
   130  Died on Table, Session ended <date> HJ <n>
   127  Referred to Finance <date> HJ <n> P. <n>
   123  Full Committee Work Session: <date> <n>:<n> am LOB <n>-<n>
   118  Ought to Pass with Amendment<amend>: MA RC <n>-<n> <date> HJ <n> P. <n>
   115  Introduced <date> and Referred to Energy and Natural Resources; SJ <n>
   113  Introduced <date> and Referred to Education; SJ <n>
   113  Executive Session: <date> <n>:<n> am LOB <n>
   112  Introduced <date> and referred to Criminal Justice and Public Safety HJ <n> P. <n>
   111  Introduced <date> and referred to Municipal and County Government HJ <n> P. <n>
   109  Public Hearing: <date> <n>:<n> am LOB <n>
   103  Refer to Interim Study, MA, VV; <date>; SJ <n>
   102  Introduced <date> and referred to Education Policy and Administration HJ <n> P. <n>
   102  Refer for Interim Study: MA VV <date> HJ <n> P. <n>
   101  Committee Report: Referred to Interim Study, <date>; Vote <n>-<n>; CC; SC <n>
    97  Subcommittee Work Session: <date> <n>:<n> am LOB <n>-<n>
    96  Introduced <date> and referred to Judiciary HJ <n> P. <n>
    94  Hearing: <date>, Room <n>-<n>, SH, <n>:<n> am; SC <n>
    93  Introduced <date> and referred to Election Law HJ <n> P. <n>
    93  Committee Report: Ought to Pass with Amendment <amend> (NT) <date> (Vote <n>-<n>; CC) HC <n> P. <n>
    93  Committee Report: Refer for Interim Study <date> (Vote <n>-<n>; CC) HC <n> P. <n>
    88  Introduced <date> and referred to Executive Departments and Administration HJ <n> P. <n>
    82  Signed by Governor Ayotte <date>; Chapter <n>; eff.<date>
    81  Amendment <amend> (NT): AA VV <date> HJ <n> P. <n>
    77  Introduced (in recess of) <date> and referred to Executive Departments and Administration HJ <n> P. <n>
    76  Ought to Pass with Amendment<amend>: MA DV <n>-<n> <date> HJ <n> P. <n>
    76  Full Committee Work Session: <date> <n>:<n> pm GP <n>
    75  Public Hearing: <date> <n>:<n> pm LOB <n>
    75  Executive Session: <date> <n>:<n> pm LOB <n>
    75  Minority Committee Report: Ought to Pass with Amendment <amend>
    73  Committee Report: Inexpedient to Legislate; Vote <n>-<n>; CC; <date>; SC <n>
    71  Committee Report: Ought to Pass <date> (Vote <n>-<n>; CC)
    70  Introduced <date> and referred to Housing HJ <n> P. <n>
    69  Committee Report: Inexpedient to Legislate, <date>, Vote <n>-<n>; SC <n>
    69  Inexpedient to Legislate: MA RC <n>-<n> <date> HJ <n> P. <n>
    69  Ought to Pass with Amendment <amend>, MA, VV; Refer to Finance Rule <n>-<n>; <date>; SJ <n>
    69  HB <n> was Removed from the Consent Calendar; <date>; SJ <n>
    68  Introduced <date> and referred to Commerce and Consumer Affairs HJ <n> P. <n>
```


## Parse: LsrSponsors.txt

{"lines": 8571, "records": 8571, "expected_fields": 5, "joined": 0, "irregular": 0}


## Parse: RollCallSummary.txt

{"lines": 419, "records": 419, "expected_fields": 15, "joined": 0, "irregular": 0}


## Parse: RollCallHistory.txt

Distinct vote values: {'Not Voting/Excused': 10878, 'Yea': 61325, 'Presiding': 325, 'Not Voting/Not Excused': 6876, 'Nay': 51794, '': 1}


## Emitted data/nh_bills_2025.json: 847 bills; {"killed": 402, "law": 305, "died_on_table": 69, "veto_sustained": 12, "nonconcurred": 19, "conference_failed": 11, "passed_chamber": 26, "unknown": 2, "enrolled": 1}


## Emitted data/nh_bills_2026.json: 1387 bills; {"killed": 544, "passed_chamber": 17, "in_committee": 77, "died_on_table": 61, "tabled": 52, "law": 337, "interim_study": 215, "conference_failed": 23, "veto_sustained": 25, "nonconcurred": 23, "recommitted": 2, "returned_to_house": 3, "veto_overridden": 7, "unknown": 1}
