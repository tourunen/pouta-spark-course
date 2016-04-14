curl -H "X-Requested-By: ambari" -X POST -d @/tmp/spark_blueprint.json -u admin:admin $1:8080/api/v1/blueprints/spark-hdfs
