// A CloudFront function serving index.html for every folder access. E.g., if a user requests the path /about, this will
// serve /about/index.html from the backing S3 bucket.
// Refer to
// https://aws.amazon.com/blogs/networking-and-content-delivery/implementing-default-directory-indexes-in-amazon-s3-backed-amazon-cloudfront-origins-using-cloudfront-functions/
// for more information.
function handler(event) {
    var request = event.request;
    var uri = request.uri;

    // Check whether the URI is missing a file name or is missing a file extension
    if (uri.endsWith("/") || !uri.includes('.')) {
        request.uri += "index.html";
    }

    return request;
}
