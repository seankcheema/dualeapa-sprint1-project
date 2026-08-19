FROM mcr.microsoft.com/mssql/server:2022-latest

ENV ACCEPT_EULA=Y
ENV SA_PASSWORD=Password!
ENV MSSQL_PID=Developer

COPY init.sql /init.sql

CMD /bin/bash -c "/opt/mssql/bin/sqlservr & sleep 30 && /opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P YourStrong!Passw0rd -i /init.sql && wait"
