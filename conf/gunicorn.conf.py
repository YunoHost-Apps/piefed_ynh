import multiprocessing

cpu_cores = multiprocessing.cpu_count()

workers = max(2, cpu_cores // 2)            # Number of worker processes. Keep low because gthread
threads = min(16, cpu_cores * 2)            # Number of threads within each worker. Should be high in gthread worker class

worker_tmp_dir = '/dev/shm'

bind = '127.0.0.1:__PORT__'
umask = 0o007
reload = False

worker_class = 'gthread'

#logging
accesslog = '-'
errorlog = '-'

max_requests = 2000
max_requests_jitter = 50
