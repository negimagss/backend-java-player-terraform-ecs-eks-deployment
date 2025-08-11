FROM eclipse-temurin:17-jdk-alpine

WORKDIR /app

COPY pom.xml mvnw ./
COPY .mvn .mvn
COPY src src
COPY Player.csv ./           # <-- add this line

RUN ./mvnw clean package -DskipTests

RUN ls -l target/

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "target/player-service-java-0.0.1-SNAPSHOT.jar"]
