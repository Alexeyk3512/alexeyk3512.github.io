FROM node:20-alpine

WORKDIR /usr/src/app

# kepubify: converts EPUB -> Kobo's .kepub.epub. Static Go binary, so Alpine is fine.
# Check https://github.com/pgaskin/kepubify/releases for newer versions / other arches.
ARG KEPUBIFY_VERSION=v4.0.4
RUN wget -q -O /usr/local/bin/kepubify \
      "https://github.com/pgaskin/kepubify/releases/download/${KEPUBIFY_VERSION}/kepubify-linux-64bit" \
    && chmod +x /usr/local/bin/kepubify \
    && kepubify --version

# kindlegen (EPUB -> MOBI for Kindle) is NOT installed: Amazon discontinued it and no
# longer distributes it. Without it, EPUB uploads to a Kindle will fail. See README.md
# for the alternatives (upload MOBI directly, or convert with Calibre).

COPY package*.json ./
RUN npm install --omit=dev

COPY . .

# index.js opens 'uploads' by relative path and deletes/recreates it on boot.
RUN mkdir -p uploads

EXPOSE 3001
CMD ["npm", "start"]
