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
struct expr {
  const char *name;
  unsigned int name_size;
};
END
  }

  if (-f $file) {
    my $converter = Convert::H::XS->new;
    $converter->process($file);

    eq_or_diff $converter->{stash}{struct} => {
      expr => [
        'const char *name',
        'unsigned int name_size',
      ],
    }, 'got correct struct info';
  }
}


done_testing;
