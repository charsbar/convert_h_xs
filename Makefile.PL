use strict;
use warnings;
use ExtUtils::MakeMaker;

my %params = (
    NAME          => 'Convert::H::XS',
    AUTHOR        => 'Kenichi Ishigaki <ishigaki@cpan.org>',
    VERSION_FROM  => 'lib/Convert/H/XS.pm',
    ABSTRACT_FROM => 'lib/Convert/H/XS.pm',
    LICENSE       => 'perl',
    PREREQ_PM     => {
        'File::Spec::Functions' => 0,
        'Text::Balanced' => 0,
    },
    BUILD_REQUIRES => {
        'Test::Differences'   => '0.10',
        'Test::More'          => '0.88',
        'Test::UseAllModules' => '0.10',
    },
    META_MERGE => {
        resources => {
            repository => 'https://github.com/charsbar/convert_h_xs',
        },
    },
);

my $eumm = $ExtUtils::MakeMaker::VERSION;
delete $params{LICENSE}          if $eumm < 6.31;
delete $params{MIN_PERL_VERSION} if $eumm < 6.48;
delete $params{META_MERGE}       if $eumm < 6.46;
delete $params{META_ADD}         if $eumm < 6.46;

if ($eumm < 6.52 && $params{CONFIGURE_REQUIRES}) {
    $params{PREREQ_PM} = {
        %{ $params{PREREQ_PM}          || {} },
        %{ $params{CONFIGURE_REQUIRES} },
    };
    delete $params{CONFIGURE_REQUIRES};
}
if ($eumm < 6.5503 && $params{BUILD_REQUIRES}) {
    $params{PREREQ_PM} = {
        %{ $params{PREREQ_PM}      || {} },
        %{ $params{BUILD_REQUIRES} },
    };
    delete $params{BUILD_REQUIRES};
}

WriteMakefile(%params);
