# https://Blogformation.net

## About

Blogformation is a serverless web application. The user supplies a public git
repository, and the application generates a blog-style code tutorial from the
project's commit history. Blogformation uses AWS for it's cloud architecture, 
and its infrastructure is implemented with Terraform (and Cloudformation for
features unsupported by terraform). The backend is written in Python.

## Architecture

![Alt text](img/blogformation.svg)
<img src="img/blogformation.svg">


## Blog Generation 

In it's current state, the blog generation algorithm is not complete; it is 
more of a proof of concept than anything. It's described by the following 
pseudocode:

```
- For each commit:
    - Create a step labeled with the commit's message
    - Create a description for the step by diffing the current commit with the 
      previous one.
```