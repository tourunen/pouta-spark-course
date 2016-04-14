curl -H "X-Requested-By: ambari" -X POST -d @/tmp/cluster_hdp.json -u admin:admin $1:8080/api/v1/clusters/$2
