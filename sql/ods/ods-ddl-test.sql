create table if not exists test
(
    name varchar(20) not null
);
insert into test (name)
values
(
 'arya'
),
    (
     'shadyar'
    ),
    (
     'zahra'
);

select * from test;