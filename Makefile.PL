use 5.008002;
use ExtUtils::MakeMaker;

WriteMakefile(
    VERSION_FROM => "Readme.pod",
    NAME         => "Sojolicious",
    ($] >= 5.005 ?
      (
       ABSTRACT_FROM  => 'Readme.pod',
       AUTHOR         => 'Nils Diewald') : ()
    ),
    PREREQ_PM => {
        'Mojolicious'     => 1.40
    }
);

