use strict;
use warnings;
use Test::More;
use Test::Differences;
use Convert::H::XS;
use File::Temp;

{
  my $dir = File::Temp->newdir;
  my $file = "$dir/foo.h";
  {
    open my $fh, ">", $file;
    print $fh <<"END";
#define FOO
#define BAR (1)
#define API __declspec(dllimport)
END
  }

  if (-f $file) {
    my $converter = Convert::H::XS->new;
    $converter->preprocess($file);

    eq_or_diff $converter->{stash}{define} => [
      ['FOO', ''],
      ['BAR', '(1)'],
      ['API', '__declspec(dllimport)'],
    ], 'got correct #define info';
  }
}


done_testing;
