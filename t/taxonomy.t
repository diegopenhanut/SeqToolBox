use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More qw(no_plan);
use strict;

require_ok ("SeqToolBox::Taxonomy");
my $obj = SeqToolBox::Taxonomy->new();
#is ("vertebrates", $obj->classify(17380163));
is ("vertebrates", $obj->classify(28195386));
is ("green_plants", $obj->classify(92090944));
is ("vertebrates", $obj->classify(28195386,"vertebrates"));
is ("9604", $obj->collapse_taxon(9606, "family"));
is ("1578", $obj->classify_taxon(417412, 1578));
is ("Escherichia coli str. K-12 substr. MG1655", $obj->get_name(511145));
#is ("cyanobacteria", $obj->classify(123610141));
is ("9606", $obj->get_taxid_by_name("Homo sapiens"));