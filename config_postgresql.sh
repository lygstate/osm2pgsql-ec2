POST_CONFIG_PATH=$1
sed -i "s/^#\?shared_buffers = .*$/shared_buffers = 2GB/" $POST_CONFIG_PATH
sed -i "s/^#\?work_mem = .*$/work_mem = 256MB/" $POST_CONFIG_PATH
sed -i "s/^#\?fsync = .*$/fsync = off/" $POST_CONFIG_PATH
sed -i "s/^#\?synchronous_commit = .*$/synchronous_commit = off/" $POST_CONFIG_PATH
sed -i "s/^#\?autovacuum = .*$/autovacuum = off/" $POST_CONFIG_PATH
sed -i "s/^#\?full_page_writes = .*$/full_page_writes = off/" $POST_CONFIG_PATH
sed -i "s/^#\?max_wal_size = .*$/max_wal_size = 3GB/" $POST_CONFIG_PATH
sed -i "s/^#\?checkpoint_completion_target = .*$/checkpoint_completion_target = 0.9/" $POST_CONFIG_PATH
sed -i "s/^#\?effective_cache_size = .*$/effective_cache_size = 6GB/" $POST_CONFIG_PATH
sed -i "s/^#\?maintenance_work_mem = .*$/maintenance_work_mem = 1GB/" $POST_CONFIG_PATH
sed -i "s/^#\?temp_buffers = .*$/temp_buffers = 512MB/" $POST_CONFIG_PATH
sed -i "s/^#\?autovacuum_work_mem = .*$/autovacuum_work_mem = -1/" $POST_CONFIG_PATH
sed -i "s/^#\?effective_io_concurrency = .*$/effective_io_concurrency = 100/" $POST_CONFIG_PATH
