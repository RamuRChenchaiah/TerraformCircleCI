def handler(event, context):
    """ This function updates the response to add a custom header. """
    response = event['Records'][0]['cf']['response']
    response['headers']['x-custom-header'] = [{
        'key': 'X-Custom-Header',
        'value': 'hello from lambda!',
    }]
    return response
