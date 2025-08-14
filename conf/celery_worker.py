#!/usr/bin/env python
import os
from app import celery, create_app


app = create_app()
if not app.debug:
    os.environ['DATABASE_URL'] = 'postgresql+psycopg2://__DB_USER__:__DB_PWD__@127.0.0.1/__DB_NAME__'
    os.environ['SERVER_NAME'] = '__DOMAIN__'

app.app_context().push()

from app.shared.tasks import maintenance
from app.shared.tasks import follows, likes, notes, deletes, flags, pages, locks, adds, removes, groups, users, blocks