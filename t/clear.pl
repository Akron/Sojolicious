use lib '../lib';
use Mojolicious::Plugin::Util::Base64url;
my $t = q{<?xml version='1.0' encoding='UTF-8'?>
<entry xmlns='http://www.w3.org/2005/Atom'>
  <id>tag:example.com,2009:cmt-0.44775718</id>  
  <author><name>test@example.com</name><uri>acct:jpanzer@google.com</uri></author>
  <thr:in-reply-to xmlns:thr='http://purl.org/syndication/thread/1.0'
      ref='tag:blogger.com,1999:blog-893591374313312737.post-3861663258538857954'>tag:blogger.com,1999:blog-893591374313312737.post-3861663258538857954
  </thr:in-reply-to>
  <content>Salmon swim upstream!</content>
  <title>};

print b64url_encode($t),"\n\n";


my $data = '
    PD94bWwgdmVyc2lvbj0nMS4wJyBlbmNvZGluZz0nVVRGLTgnPz4KPGVudHJ5IHhtbG5zPS
    dodHRwOi8vd3d3LnczLm9yZy8yMDA1L0F0b20nPgogIDxpZD50YWc6ZXhhbXBsZS5jb20s
    MjAwOTpjbXQtMC40NDc3NTcxODwvaWQ-ICAKICA8YXV0aG9yPjxuYW1lPnRlc3RAZXhhbX
    BsZS5jb208L25hbWU-PHVyaT5hY2N0OmpwYW56ZXJAZ29vZ2xlLmNvbTwvdXJpPjwvYXV0a
    G9yPgogIDx0aHI6aW4tcmVwbHktdG8geG1sbnM6dGhyPSdodHRwOi8vcHVybC5vcmcvc3l
    uZGljYXRpb24vdGhyZWFkLzEuMCcKICAgICAgcmVmPSd0YWc6YmxvZ2dlci5jb20sMTk5O
    TpibG9nLTg5MzU5MTM3NDMxMzMxMjczNy5wb3N0LTM4NjE2NjMyNTg1Mzg4NTc5NTQnPnR
    hZzpibG9nZ2VyLmNvbSwxOTk5OmJsb2ctODkzNTkxMzc0MzEzMzEyNzM3LnBvc3QtMzg2M
    TY2MzI1ODUzODg1Nzk1NAogIDwvdGhyOmluLXJlcGx5LXRvPgogIDxjb250ZW50PlNhbG1
    vbiBzd2ltIHVwc3RyZWFtITwvY29udGVudD4KICA8dGl0bGU-U2FsbW9uIHN3aW0gdXBzdH
    JlYW0hPC90aXRsZT4KICA8dXBkYXRlZD4yMDA5LTEyLTE4VDIwOjA0OjAzWjwvdXBkYXRl
    ZD4KPC9lbnRyeT4KICAgIA';

print b64url_decode($data);

