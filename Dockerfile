FROM swift:5.2

RUN apt-get update && apt-get install -y \
	build-essential \
	libserd-dev \
	sqlite3 \
	libsqlite3-dev \
	&& rm -rf /var/lib/apt/lists/*

RUN mkdir /work
WORKDIR /work

COPY Package.swift .
COPY Sources Sources
COPY Tests Tests
COPY rdf-tests rdf-tests
COPY rdf-tests-12 rdf-tests-12
RUN swift build --build-tests

ENV KINEO_W3C_TEST_PATH /work/rdf-tests
ENV KINEO_W3C_TEST_PATH_12 /work/rdf-tests-12

CMD ["swift", "test", "--parallel"]
