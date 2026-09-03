# epic 1, story 1.3: Deciding between views, materialised views and dynamic table


### Views:

What it is?

views are basically saved queries, instead of always typing out 
a query, u can reuse this.

Pros:
Always updated, the reason? it always needs to be run again.

Cons: 
Takes time to run again and again.


When to use in this project?

my theory? I'd say we use it for logic, validation and reusable
reporting logic, before serving the data to analysts.


### Materialised Views:

same as regular views but values are saved to disk.

Pros:
its fast.

Cons:
needs to be updated manually.

when to use?

reporting layer and can be given to analysts for their dashboards
to be built on.


### Dynamic Tables:

It is to some sort combination of the two above.

Pros:
updated,
values are saved.

Cons:
less control over when data is exposed to downstream users.


## Conclusion?

I have decided to go with regular views and materialised views.

The reasoning is that they have different purposes and together
they give us reusable logic, data quality control and fast
dashboard queries.


Why i did not choose Dynamic Tables:

my theory:

if it is constantly updated and given to downstream users, if
something goes wrong upstream, the incomplete data could be
automatically propagated downstream.

For example, if match data arrives late during scheduled ingestion,
a lot of NULL values could show up and incomplete data could reach
the dashboards.

**Solution**

Use the regular views for ourselves and implement checks.

For example, if NULL values are greater than 10% of the relevant
data, don't push the data to the serving layer and raise an alert
so it can be investigated.

Once the data passes the checks, refresh the materialised views.
The materialised views are then available for the analysts to build
their dashboards on.


_The Architecture:_

RAW STATS BOMB DATA
        ↓
TRANSFORMATION
        ↓
ODS_MATCH_EVENTS
        ↓
REGULAR VIEWS ----
        ↓
DATA QUALITY CHECKS until here it will not be serving layer
        ↓
MATERIALISED VIEWS
        ↓
DASHBOARDS