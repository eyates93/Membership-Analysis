--First I check to see if the temp table (which is used as in my analysis) has already been created, if it still exists at runtime, then delete it.
IF OBJECT_ID(N'tempdb..#temptable') IS NOT NULL
BEGIN
DROP TABLE #temptable
END
GO

--I write a CTE to return all of the Membership agreements for a given time period. I include all of the nessesary details incudling their location, and when the membership starts and ends.
with HSP as
(
select distinct
    ServiceAgreementID,
	agr.Name as 'Service Agreement Name',
    CurrentEvent_ServiceAgreementEventTypeID as 'SA Event Type ID', 
    ServiceLocation_LocationID,
    sl.Name,
	StartOn,
    EndOn,
	Type_ServiceAgreementTypeID as 'Coverage Type ID',
	CurrentEvent_LocationEventTypeID as 'Location Event Type ID',
	ServiceAgreementAmount,
	BillingFrequency_ServiceAgreementBillingFrequencyID,
	VisitsPerYear,
	agr.BranchNumber


from FSA.ServiceAgreements agr
left join FSA.Locations sl 
	on agr.ServiceLocation_LocationID = sl.LocationId


where agr.ServiceLocation_LocationID is not null --Location ID is not null
and year(EndOn) in (2022, 2023)
and Type_ServiceAgreementTypeID != -3 --Service Agreement Type is not 'Warranty'

)


--I write another CTE that is used to pull of the companies service branches that had a go live date before a certain time period.
,ValidServiceOrders as (
SELECT distinct fSO.BusinessUnitId, CGO.BranchNumber
FROM  FSA.factServiceOrder as fSO

INNER JOIN FSA.DimBusinessUnit as BU
	on fSO.BusinessUnitId = BU.BusinessUnitId

INNER JOIN xyz.PBI_Connect_Branch_GoLive as CGO
	on BU.BusinessUnitNumber = CGO.BranchNumber

where CGO.GoLiveDate <= '2022-06-01'
)


--I then create a flat table called temp table where I determine weather a customer had an active membership during their service call. 
select 
fSO.ServiceOrderID
,Cast(fSO.EndOnDate as date) as 'Service Date'
,HSP.StartOn as 'Membership Start'
,HSP.EndOn as 'Membership End'
,CASE
	WHEN fSO.EndOnDate between HSP.StartOn and HSP.EndOn 
	THEN 'HSP Customer'
	ELSE 'Non HSP'
	END AS 'HSP Flag'
,CASE
	WHEN fSO.EndOnDate between HSP.StartOn and HSP.EndOn 
	THEN 1
	ELSE Null
	END AS 'Member'
,CASE
	WHEN fSO.EndOnDate between HSP.StartOn and HSP.EndOn 
	THEN Null
	ELSE 1
	END AS 'Non-Member'
,CGO.BranchNumber
,CGO.BranchName
,CGO.GoLiveDate
into #temptable
from FSA.factServiceOrder as fSO
left join HSP
	on HSP.ServiceLocation_LocationID = fSO.ServiceLocationId		--Join on Location ID
	and fSO.EndOnDate between HSP.StartOn and HSP.EndOn				--Service Order End Date is between Membership Start and End dates

inner join ValidServiceOrders as vSO
	on fSO.BusinessUnitId = vSO.BusinessUnitId

left join xyz.PBI_Connect_Branch_GoLive as CGO
	on vSO.BranchNumber = CGO.BranchNumber

where 
--SO.Type_ServiceOrderTypeID = -2  --Service Order is a Serivce Order and not a Quote, PO or Project
--and HSP.[Coverage Type ID] != -3 --Service Agreement Type is not 'Warranty'
 year(fSO.EndOnDate) in (2022, 2023)
--and ServiceLineId = 10 --HVAC Service
--and IsDeleted = 0
--and SourceId = 1	--Only sourced from Residential.
and CurrentEventDetailId not in ( -12, -1010) --or CurrentEventDetailId is null) --is not Void or Void Test (also excluding event types that are null
--and CGO.GoLiveDate <= '2022-06-01'

order by fSO.EndOnDate asc


--Return the flat table view
SELECT  *
FROM    #temptable



--Here is query that returns an aggregated view of the same result set as above. Here I get a break down by month and branch of how many service calls they had, and of those calls, how many and what percentage of them were members and not members.
Select
Cast( DATEADD(MONTH, DATEDIFF(MONTH, 0, [Service Date]), 0) AS DATE) AS 'Month Year'
,BranchNumber
,BranchName
,Count(*) as 'Total Count'
,SUM(Member) as 'Member Count'
,AVG(CASE WHEN t.[Non-Member] is null THEN 1.0 ELSE 0 END) '% of Membership'
,SUM([Non-Member]) as 'Non-Member Count'
,AVG(CASE WHEN t.Member is null THEN 1.0 ELSE 0 END) '% of Non-Membership'

FROM    #temptable as t

WHERE [Service Date] between '2022-05-01' and '2023-06-22'

Group By DATEADD(MONTH, DATEDIFF(MONTH, 0, [Service Date]), 0), year([Service Date])
		,month([Service Date])
		,BranchNumber
		,BranchName

Order By year([Service Date])
		,month([Service Date])