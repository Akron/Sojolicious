use Test::More tests => 216;
use File::Temp qw/:POSIX/;
use Data::Dumper 'Dumper';
use strict;
use warnings;

$|++;

use lib '../lib';
use_ok 'Sojolicious::Oro';

my $_init_name =
'CREATE TABLE Name (
   id             INTEGER PRIMARY KEY,
   prename        TEXT NOT NULL,
   surname        TEXT
 )';

my $_init_content =
'CREATE TABLE Content (
   id            INTEGER PRIMARY KEY,
   content       TEXT,
   title         TEXT,
   author_id     INTEGER
 )';

my $_init_book =
'CREATE TABLE Book (
   id        INTEGER PRIMARY KEY,
   title     TEXT,
   year      INTEGER,
   author_id INTEGER,
   FOREIGN KEY (author_id) REFERENCES Name(id)
)';

# Real DB:
my $db_file = tmpnam();

ok(my $oro = Sojolicious::Oro->new(
  $db_file => sub {
    for ($_[0]) {
      $_->do($_init_name);
      $_->do($_init_content);
      $_->do($_init_book);
    };
  }), 'Init real db');

ok($oro->insert(Content => {
  title => 'Test', content => 'Value 1'
}), 'Before disconnect');

ok($oro->dbh->disconnect, 'Disonnect');

ok($oro->insert(Content => {
  title => 'Test', content => 'Value 2'
}), 'Reconnect');

ok($oro->on_connect(
  sub {
    ok(1, 'on_connect release 1')}
), 'on_connect');

ok($oro->on_connect(
  testvalue => sub {
    ok(1, 'on_connect release 2')}
), 'on_connect');

ok(!$oro->on_connect(
  testvalue => sub {
    ok(0, 'on_connect release 3')}
), 'on_connect');

ok($oro->dbh->disconnect, 'Disconnect');

ok($oro->insert(Content => {
  title => 'Test', content => 'Value 3'
}), 'Reconnect');

unlink $db_file;

$db_file = '';

ok($oro = Sojolicious::Oro->new(
  $db_file => sub {
    for ($_[0]) {
      $_->do($_init_name);
      $_->do($_init_content);
      $_->do($_init_book);
    };
  }), 'Init temp db');

ok($oro->insert(Content => {
  title => 'Test', content => 'Value 1'
}), 'Before disconnect');

ok($oro->dbh->disconnect, 'Disonnect');

{
  local $SIG{__WARN__} = sub {};
  ok(!$oro->insert(Content => {
    title => 'Test', content => 'Value 2'
  }), 'Reconnect');
};

# In memory db
$db_file = ':memory:';

ok($oro = Sojolicious::Oro->new(
  $db_file => sub {
    for ($_[0]) {
      $_->do($_init_name);
      $_->do($_init_content);
      $_->do($_init_book);
    };
  }), 'Init memory db');

{
  local $SIG{__WARN__} = sub {};

  # Negative checks
  ok($oro->insert(Content => { title => 'Check!',
			       content => 'This is content.'}), 'Insert');

  ok($oro->insert(Name => { prename => 'Akron',
			    surname => 'Sojolicious'}), 'Insert');

  ok(!$oro->insert(Content_unknown => {title => 'Hey!'}), 'Insert');

  ok(!$oro->insert(Name => { surname => 'Rodriguez'}), 'Insert');

  ok(!$oro->update(Content_unknown =>
		     { content => 'This is changed content.' } =>
		       { title => 'Check not existent!' }), 'Update');

  ok(!$oro->update(Content =>
		     { content_unkown => 'This is changed content.' } =>
		       { title => 'Check not existent!' }), 'Update');

  ok(!$oro->select('Content_2'), 'Select');

  ok(!$oro->merge( Content_unknown =>
		     { content => 'Das ist der fuenfte content.' } =>
		       { 'title' => 'Noch ein Check!' }),
     'Merge');

  ok(!$oro->insert(Content => [qw/titles content/] =>
		     ['CheckBulk','Das ist der elfte content']),
     'Bulk Insert');

  ok(!$oro->insert(Content => [qw/title content/] =>
		     ['CheckBulk','Das ist der zwoelfte content', 'Yeah']),
     'Bulk Insert');

  ok(!$oro->insert(Content => [qw/title content/]), 'Bulk Insert');
};


$oro = Sojolicious::Oro->new(
  $db_file => sub {
    shift->do($_init_name);
  });

ok($oro, 'Created');
ok($oro->created, 'Created');

if ($oro->created) {
  $oro->do($_init_content);
  $oro->do($_init_book);
  $oro->do('CREATE INDEX i ON Book(author_id)');
};


# Insert:
ok($oro->insert(Content => { title => 'Check!',
			     content => 'This is content.'}), 'Insert');

ok($oro->insert(Name => { prename => 'Akron',
			  surname => 'Sojolicious'}), 'Insert');

# Update:
ok($oro->update(Content =>
		  { content => 'This is changed content.' } =>
		    { title => 'Check!' }), 'Update');

is($oro->last_insert_id, 1, 'Row id');

like($oro->last_sql, qr/^update/i, 'SQL command');

ok(!$oro->update(Content =>
		  { content => 'This is changed content.' } =>
		    { title => 'Check not existent!' }), 'Update');

# Load:
my $row;
ok($row = $oro->load(Content => { title => 'Check!' }), 'Load');

is ($row->{content}, 'This is changed content.', 'Load');

ok($oro->insert(Content =>
		  { title => 'Another check!',
		    content => 'This is second content.' }), 'Insert');

ok($oro->insert(Content =>
		  { title => 'Check!',
		    content => 'This is third content.' }), 'Insert');

my $array;
ok($array = $oro->select(Content => { title => 'Check!' }), 'Select');
is($array->[0]->{content}, 'This is changed content.', 'Select');
is($array->[1]->{content}, 'This is third content.', 'Select');

ok($row = $oro->load(Content => { title => 'Another check!' } ), 'Load');
is($row->{content}, 'This is second content.', 'Check');

is($oro->delete(Content => { title => 'Another check!' }), 1, 'Delete');
ok(!$oro->delete(Content => { title => 'Well.' }), 'Delete');

$oro->select('Content' => sub {
	       like(shift->{content},
		    qr/This is (?:changed|third) content\./,
		    'Select');
	     });

my $once = 1;
$oro->select('Content' => sub {
	       ok($once--, 'Select Once');
	       like(shift->{content},
		    qr/This is (?:changed|third) content\./,
		    'Select Once');
	       return -1;
	     });

$oro->select('Name' => ['prename'] =>
	       sub {
		 ok(!exists $_[0]->{surname}, 'Fields');
		 ok($_[0]->{prename}, 'Fields');
	     });

ok($oro->update( Content =>
		   { content => 'Das ist der vierte content.' } =>
		     { 'title' => 'Check!' }), # Changes two entries!
   'Merge');

ok($oro->merge( Content =>
		  { content => 'Das ist der fuenfte content.' } =>
		    { 'title' => 'Noch ein Check!' }),
   'Merge');

ok($oro->merge( Content =>
		  { content => 'Das ist der sechste content.' } =>
		    { 'title' => ['Noch ein Check!', 'FooBar'] }),
   'Merge');

is($oro->select('Content' =>
		  { content => 'Das ist der sechste content.'}
		)->[0]->{title}, 'Noch ein Check!', 'Title');

ok($oro->merge( Content =>
		  { content => 'Das ist der siebte content.' } =>
		    { 'title' => ['HelloWorld', 'FooBar'] }),
   'Merge');

ok(!$oro->select('Content' =>
		   { content => 'Das ist der siebte content.'}
		 )->[0]->{title}, 'Title');


ok($oro->delete('Content' => { content => ['Das ist der siebte content.']}),
   'Delete');

is($oro->last_insert_id, 5, 'Row id');

ok($oro->insert(Content => [qw/title content/] =>
	   ['CheckBulk','Das ist der sechste content'],
	   ['CheckBulk','Das ist der siebte content'],
	   ['CheckBulk','Das ist der achte content'],
	   ['CheckBulk','Das ist der neunte content'],
	   ['CheckBulk','Das ist der zehnte content']), 'Bulk Insert');

ok($array = $oro->select('Content' => [qw/title content/]), 'Select');
is(@$array, 8, 'Check Select');

ok($array = $oro->load('Content' => {content => 'Das ist der achte content'}), 'Load');
is($array->{title}, 'CheckBulk', 'Check Select');

ok($oro->delete('Content', { title => 'CheckBulk'}), 'Delete Table');

ok($array = $oro->select('Content' => [qw/title content/]), 'Select');
is(@$array, 3, 'Check Select');

ok($array = $oro->select('Content' => ['id'] => { id => [1..4] }), 'Select');
is('134', join('', map($_->{id}, @$array)), 'Where In');


my ($rv, $sth) = $oro->prep_and_exec('SELECT count("*") as count FROM Content');
ok($rv, 'Prep and Execute');
is($sth->fetchrow_arrayref->[0], 3, 'Prep and exec');

$sth->finish;

ok($oro->dbh->{AutoCommit}, 'Transaction');
$oro->dbh->begin_work;
ok(!$oro->dbh->{AutoCommit}, 'Transaction');

foreach my $x (1..10) {
  $oro->insert(Content => { title => 'Transaction',
			    content => 'Das ist der '.$x.'. Eintrag'});
};

ok(!$oro->dbh->{AutoCommit}, 'Transaction');
$oro->dbh->commit;
ok($oro->dbh->{AutoCommit}, 'Transaction');

($rv, $sth) = $oro->prep_and_exec('SELECT count("*") as count FROM Content');
ok($rv, 'Prep and Execute');
is($sth->fetchrow_arrayref->[0], 13, 'Fetch row.');
$sth->finish;

ok($oro->dbh->{AutoCommit}, 'Transaction');
$oro->dbh->begin_work;
ok(!$oro->dbh->{AutoCommit}, 'Transaction');

foreach my $x (1..10) {
  $oro->insert(Content => { title => 'Transaction',
			    content => 'Das ist der '.$x.'. Eintrag'});
};

ok(!$oro->dbh->{AutoCommit}, 'Transaction');
$oro->dbh->rollback;
ok($oro->dbh->{AutoCommit}, 'Transaction');

($rv, $sth) = $oro->prep_and_exec('SELECT count("*") as count FROM Content');
ok($rv, 'Prep and Execute');
is($sth->fetchrow_arrayref->[0], 13, 'Fetch row.');
$sth->finish;

is($oro->count('Content'), 13, 'count');

my $load = $oro->load('Content' => ['count(*):number']);
is($load->{number}, 13, 'AS feature');

ok($oro->txn(
  sub {
    foreach (1..100) {
      $oro->insert(Content => { title => 'Check'.$_ });
    };
    return 1;
  }), 'Transaction');

is($oro->count('Content'), 113, 'Count');

ok(!$oro->txn(
  sub {
    foreach (1..100) {
      $oro->insert(Content => { title => 'Check'.$_ });
      return -1 if $_ == 50;
    };
    return 1;
  }), 'Transaction');

is($oro->count('Content'), 113, 'Count');

# Nested transactions:

ok($oro->txn(
  sub {
    my $val = 1;

    foreach (1..100) {
      $oro->insert(Content => { title => 'Check'.$val++ });
    };

    ok(!$oro->txn(
      sub {
	foreach (1..100) {
	  $oro->insert(Content => { title => 'Check'.$val++ });
	  return -1 if $_ == 50;
	};
      }), 'Nested Transaction 1');

    ok($oro->txn(
      sub {
	foreach (1..100) {
	  $oro->insert(Content => { title => 'Check'.$val++ });
	};
	return 1;
      }), 'Nested Transaction 2');

    return 1;
  }), 'Transaction');

is($oro->count('Content'), 313, 'Count');


# Less than 500
my @massive_bulk;
foreach (1..450) {
  push(@massive_bulk, ['MassiveBulk', 'Content '.$_ ]);
};

ok($oro->insert(Content => [qw/title content/] => @massive_bulk), 'Bulk Insert');

is($oro->count(Content => {title => 'MassiveBulk'}), 450, 'Bulk Check');

# More than 500
@massive_bulk = ();
foreach (1..4500) {
  push(@massive_bulk, ['MassiveBulk', 'Content '.$_ ]);
};

ok($oro->insert(Content => [qw/title content/] => @massive_bulk), 'Bulk Insert 2');

is($oro->count(Content => {title => 'MassiveBulk'}), 4950, 'Bulk Check 2');

is($oro->count('Content'), 5263, 'Count');

is($oro->delete('Content'), 5263, 'Delete all');

is($oro->count('Content'), 0, 'Count');

my ($content, $name);
ok($content = $oro->table('Content'), 'Content');
ok($name = $oro->table('Name'), 'Name');

is($content->insert({ title => 'New Content'}), 1, 'Insert with table');
is($name->insert({
  prename => 'Akron',
  surname => 'Fuxfell'
}),1 , 'Insert with table');

is($name->update({
  surname => 'Sojolicious'
},{
  prename => 'Akron',
}), 2, 'Update with table');

is($name->update({
  surname => 'Sojolicious'
},{
  prename => 'Akron',
}), 2, 'Update with table');

is(@{$name->select({ prename => 'Akron' })}, 2, 'Select with Table');

ok($name->delete({
  id => 1
}), 'Delete with Table');

ok(!$name->load({ id => 1 }), 'Load with Table');

ok($name->merge(
  { prename => 'Akron' },
  { surname => 'Sojolicious' }
), 'Merge with Table');

is($content->insert({ title => 'New Content 2'}), 1, 'Insert with table');
is($content->count, 2, 'Count with Table');

is($content->insert({ title => 'New Content 3'}), 1, 'Insert with table');

is_deeply($content->select(
  ['title'] => {
    -order => '-title',
  }), [
    { title => 'New Content 3' },
    { title => 'New Content 2' },
    { title => 'New Content' }
  ], 'Offset restriction');

is_deeply($content->select(
  ['title'] => {
    -order => '-title',
    -limit => 2
  }), [
    { title => 'New Content 3' },
    { title => 'New Content 2' }
  ], 'Limit restriction');

is_deeply($content->select(
  ['title'] => {
    -order => '-title',
    -limit => 2,
    -offset => 1
  }), [
    { title => 'New Content 2' },
    { title => 'New Content' }
  ], 'Order restriction');

ok($content->update({ content => 'abc' } => {title => 'New Content'}), 'Update');;
ok($content->update({ content => 'cde' } => {title => 'New Content 2'}), 'Update');
ok($content->insert({ content => 'cdf',  title => 'New Content 1'}),'Insert');;
ok($content->update({ content => 'efg' } => {title => 'New Content 2'}),'Update');;
ok($content->update({ content => 'efg' } => {title => 'New Content 3'}),'Update');

is(join(',',
	map($_->{id},
	    @{$content->select(
	      ['id'] =>
		{
		  -order => ['-content', '-title']
		}
	      )})), '3,2,4,1', 'Combined Order restriction');

ok($content->insert(
  ['title', 'content'] =>
    ['Bulk 1', 'Content'],
    ['Bulk 2', 'Content'],
    ['Bulk 3', 'Content'],
    ['Bulk 4', 'Content']), 'Bulk Insertion');

# Joins:
ok($oro->delete('Content'), 'Truncate');
ok($oro->delete('Name' => { -secure => 1 }), 'Truncate securely');

my %author;

$oro->txn(
  sub {
    $oro->insert(Name => { prename => 'Akron' });
    $author{akron} = $oro->last_insert_id;

    $oro->insert(Name => { prename => 'Fry' });
    $author{fry} = $oro->last_insert_id;

    $oro->insert(Name => { prename => 'Leela' });
    $author{leela} = $oro->last_insert_id;

    foreach (qw/Akron Fry Leela/) {
      my $id = $author{lc($_)};
      ok($oro->insert(Content => ['title', 'content', 'author_id'] =>
	  [$_.' 1', 'Content', $id],
          [$_.' 2', 'Content', $id],
          [$_.' 3', 'Content', $id],
          [$_.' 4', 'Content', $id]), 'Bulk Insertion');
    };

    foreach (qw/Akron Fry Leela/) {
      my $id = $author{lc($_)};
      ok($oro->insert(Book => ['title', 'year', 'author_id'] =>
	  [$_."'s Book 1", 14, $id],
          [$_."'s Book 2", 20, $id],
          [$_."'s Book 3", 19, $id],
          [$_."'s Book 4", 8, $id]), 'Bulk Insertion');
    };

  });

# distinct
is(@ { $oro->select('Book' => ['author_id']) }, 12, 'Books');
is(@ { $oro->select('Book' => ['author_id'] => {
  -distinct => 1
})}, 3, 'Distinct Books');

my $found = $oro->select([
  Name => ['prename:author'] => { id => 1 },
  Content => ['title'] => { author_id => 1 }
] => { author => 'Fry'} );

is(@$found, 4, 'Joins');

ok($found = $oro->select([
  Name => ['prename:author'] => { id => 1 },
  Book => ['title:title','year:year'] => { author_id => 1 }
] => { author => 'Fry' } ), 'Joins');

my $last_sql = $oro->last_sql;

ok($found = $oro->select([
  Name => ['prename:author'] => { id => 1 },
  Book => ['title','year'] => { author_id => 1 }
] => { author => 'Fry' } ), 'Joins');

is($oro->last_sql, $last_sql, 'Automated aliases');

my $year;
$year += $_->{year} foreach @$found;

is($year, 61, 'Joins');

ok($found = $oro->select([
  Name => { id => 1 },
  Book => ['title:title'] => { author_id => 1 }
] => { prename => 'Fry' } ), 'Joins');

is(@$found, 4, 'Joins');

my $books = $oro->table([
  Name => { id => 1 },
  Book => ['title:title'] => { author_id => 1 }
]);

ok($found = $books->select({ prename => 'Leela'}), 'Joins with table');
is(@$found, 4, 'Joins');

is($books->count({ prename => 'Leela' }), 4, 'Joins with count');
ok($books->load({ prename => 'Leela' })->{title}, 'Joins with load');


# Insert with default
ok($oro->delete('Name'), 'Truncate');
ok($oro->insert(Name =>
		  ['prename', [surname => 'Meier']] =>
		    map { [$_] } qw/Sabine Peter Michael Frank/ ),
   'Insert with default');

my $meiers = $oro->select('Name');
is((@$meiers), 4, 'Default inserted');
is($meiers->[0]->{surname}, 'Meier', 'Default inserted');
is($meiers->[1]->{surname}, 'Meier', 'Default inserted');
is($meiers->[2]->{surname}, 'Meier', 'Default inserted');
is($meiers->[3]->{surname}, 'Meier', 'Default inserted');

ok($oro->delete('Book'), 'Truncate');
ok($oro->insert(Book =>
		  ['title',
		   [year => 2012],
		   [author_id => 4]
		 ] =>
		   map { [$_] } qw/Misery Carrie It/ ),
   'Insert with default');

my $king = $oro->select('Book');
is((@$king), 3, 'Default inserted');
is($king->[0]->{year}, 2012, 'Default inserted');
ok($king->[0]->{title}, 'Default inserted');
is($king->[1]->{year}, 2012, 'Default inserted');
ok($king->[1]->{title}, 'Default inserted');
is($king->[2]->{year}, 2012, 'Default inserted');
ok($king->[2]->{title}, 'Default inserted');

ok($oro->delete('Content'), 'Truncate');

my @array;
push(@array, ['ContentBulk', $_, $_]) foreach 1..1111;

ok($oro->insert(Content =>
		  [qw/title content author_id/] =>
		    @array), 'Bulk Insert');

is($oro->count('Content'), 1111, 'Count bulk insert');

# Select Operators
my $result = $oro->select(Content => { author_id => [4,5] });
is($result->[0]->{content}, '4', 'Select with array');
is($result->[1]->{content}, '5', 'Select with array');

# lt
$result = $oro->select(Content => { author_id => { lt => 2 } });
is($result->[0]->{content}, '1', 'Select with lt');
is(@$result,1, 'Select with lt');

# <
$result = $oro->select(Content => { author_id => { '<' => 2 } });
is($result->[0]->{content}, '1', 'Select with <');
is(@$result,1, 'Select with <');

# gt
$result = $oro->select(Content => { author_id => { gt => 1110 } });
is($result->[0]->{content}, '1111', 'Select with gt');
is(@$result, 1, 'Select with gt');

# >
$result = $oro->select(Content => { author_id => { '>' => 1110 } });
is($result->[0]->{content}, '1111', 'Select with >');
is(@$result, 1, 'Select with >');

# le
$result = $oro->select(Content => { author_id => { le => 2 } });
is($result->[0]->{content}, '1', 'Select with le');
is($result->[1]->{content}, '2', 'Select with le');
is(@$result,2, 'Select with le');

# <=
$result = $oro->select(Content => { author_id => { '<=' => 2 } });
is($result->[0]->{content}, '1', 'Select with <=');
is($result->[1]->{content}, '2', 'Select with <=');
is(@$result,2, 'Select with <=');

# ge
$result = $oro->select(Content => { author_id => { ge => 1110 } });
is($result->[0]->{content}, '1110', 'Select with ge');
is($result->[1]->{content}, '1111', 'Select with ge');
is(@$result, 2, 'Select with ge');

# >=
$result = $oro->select(Content => { author_id => { '>=' => 1110 } });
is($result->[0]->{content}, '1110', 'Select with >=');
is($result->[1]->{content}, '1111', 'Select with >=');
is(@$result, 2, 'Select with >=');

# ==
$result = $oro->select(Content => { author_id => { '==' => 555 } });
is($result->[0]->{content}, '555', 'Select with ==');
is(@$result, 1, 'Select with ==');

# =
$result = $oro->select(Content => { author_id => { '=' => 555 } });
is($result->[0]->{content}, '555', 'Select with =');
is(@$result, 1, 'Select with =');

# eq
$result = $oro->select(Content => { author_id => { eq => 555 } });
is($result->[0]->{content}, '555', 'Select with eq');
is(@$result, 1, 'Select with eq');

# ne
$result = $oro->select(Content => { author_id => { ne => 1 } });
is(@$result, 1110, 'Select with ne');

# !=
$result = $oro->select(Content => { author_id => { '!=' => 1 } });
is(@$result, 1110, 'Select with !=');

# Between
$result = $oro->select(Content => { author_id => { between => [3,5] } });
is($result->[0]->{content}, '3', 'Select with between');
is($result->[1]->{content}, '4', 'Select with between');
is($result->[2]->{content}, '5', 'Select with between');

# Combining
$result = $oro->select(Content => { author_id => { le => 5, ge => 3 } });
is($result->[0]->{content}, '3', 'Select with combination');
is($result->[1]->{content}, '4', 'Select with combination');
is($result->[2]->{content}, '5', 'Select with combination');

$oro->delete('Name');

ok($oro->insert(Name =>
		  ['prename', [surname => 'Meier']] =>
		    map { [$_] } qw/Sabine Peter Michael Frank/ ),
   'Insert with default');

# Like
$result = $oro->select(Name => { prename => { like => '%e%' } });
is(@$result, 3, 'Select with like');

# Glob
$result = $oro->select(Name => { prename => { glob => '*e*' } });
is(@$result, 3, 'Select with glob');

# Negation like
$result = $oro->select(Name => { prename => { not_like => '%e%' } });
is(@$result, 1, 'Select with not_like');

# Negation Glob
$result = $oro->select(Name => { prename => { not_glob => '*e*' } });
is(@$result, 1, 'Select with not_glob');

# Negation Between
$result = $oro->select(Content => { author_id => { not_between => [2, 1110] } });
is($result->[0]->{content}, '1', 'Select with not_between');
is($result->[1]->{content}, '1111', 'Select with not_between');
is(@$result, 2, 'Select with not_between');

# Driver test
is($oro->driver, 'SQLite', 'Driver');

# Treatment-Test
my $treat_content = sub {
  return ('content', sub { uc($_[0]) });
};

ok($oro->insert(Content => {
  title => 'Not Bulk',
  content => 'Simple Content' }), 'Insert');

ok($row = $oro->load(Content =>
		       ['title', [$treat_content => 'uccont'], 'content'] =>
			 { title => { ne => 'ContentBulk' }}
), 'Load with Treatment');

is($row->{uccont}, 'SIMPLE CONTENT', 'Treatment');

$oro->select(Content =>
	       ['title', [$treat_content => 'uccont'], 'content'] =>
		 { title => { ne => 'ContentBulk' }},
	     sub {
	       is($_[0]->{uccont}, 'SIMPLE CONTENT', 'Treatment');
	     });

$oro->insert(Name => { prename => '0045', surname => 'xyz777'});

is($oro->load(Name => { surname => 'xyz777' })->{prename},
   '0045',
   'Prepended Zeros');

ok(length($oro->explain(
  'SELECT
     Name.prename AS "author",
     Book.title AS "title",
     Book.year AS "year"
   FROM
     Name,
     Book
   WHERE
     Name.id = Book.author_id AND
     author_id = ?', [4])) > 0, 'Explain');

__END__
