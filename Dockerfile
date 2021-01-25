FROM python

ENV virtualenv smrt
ENV VIRTUAL_ENV /smrt
ENV PATH /smrt:$PATH
RUN which python
RUN python -m pip install Django

COPY . ./smrt
WORKDIR /smrt/smrt

CMD python manage.py runserver 0.0.0.0:8000


EXPOSE 8000
