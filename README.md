# flask-deploy

A deployment pattern to quickly deploy Python Flask applications to a Linux server

## Flask Requirements

* You must have a `requirements.txt` file
* Your main app file must be `run.py`
* The main entry handler must be `app.

## To test it

> On Amazon Linux, you need to `yum install -y git` first

* Install a fresh Ubuntu or Amazon Linux instance.
* Clone this repo on the server : `git clone https://github.com/massyn/flask-deploy`
* Deploy the flask app

```
cd flask-deploy
bash ./deploy.sh helloworld ./src hello.massyn.net;hello2.massyn.net 5001
```

