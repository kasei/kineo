FROM swift:4.2

RUN apt-get update && apt-get install -y \
	build-essential \
	libserd-dev \
	&& rm -rf /var/lib/apt/lists/*

RUN mkdir /work
WORKDIR /work

COPY Package.swift .
COPY Sources Sources
COPY Tests Tests
COPY rdf-tests rdf-tests
RUN swift build

ENV KINEO_W3C_TEST_PATH /work/rdf-tests
CMD ["swift", "test", "--parallel"]
